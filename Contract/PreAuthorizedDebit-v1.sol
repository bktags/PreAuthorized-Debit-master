pragma solidity ^0.4.22;


contract PreAuthorizedDebit {
    // The role of the developer is to create bank initalize Bank addresses.
    // It is assumed that the developer is trusted by all banks.
    // The only function associated with the developer is createBank().
    address developer;
    
    // Assumed to be initialized by the client through an API.
    // Parties represent individuals and companies. Their identity is verified by the bank
    // off-chain (e.g. presentation of ID, business number, proof of income, etc.)
    // In the context of PAD, parties can be both Payor and Payee.
    struct Party { 
        string name;
        bool idVerified;  // identification verified by bank.
    }
    
    // Initalized by bank. Banks grant bank accounts to parties.
    // Parties can own multiple accounts. 
    // Addresses of bank accounts should be stored off-chain.
    struct BankAccount {
        bool isOpen; // Banks can open and close accounts.
        address owner;
        address bank;
        uint256 centsBalance;
        string transitNumber;
        string institutionNumber;
        string accountNumber;
    }

    // Banks are able to create bank accounts and it is assumed that they are using this
    // smart contract as the backend to a website or application they have developed for
    // consumers.
    // Banks can only debit and credit accounts that they themselves manage.
    struct Bank {
        string name;
        string businessNumber;
        bool isBank;
    }
    
    enum PaymentType {Fixed, MaximumLimited, Unlimited}
    enum PaymentFrequency {Daily, Weekly, BiWeekly, Monthly, Annual, Sporadic}

    // Filled by payor. Address passed to payee off-chain.
    // The form represents the permissions for payee to debit payor's bank account.
    struct PADAgreementForm {
        address payorAddress;
        address payorBankAccount;
        address payeeAddress;
        PaymentType paymentType; 
        PaymentFrequency paymentFrequency; 
        string expiryDate;  // 'yyyy-mm-dd'; used by bank.
        uint256 maxPaymentAmount;
        bool isAuthorized;  // Can only be toggled by payor.
    }

    // Filled by payee. Payment address passed to payor's and payee's banks off-chain.
    struct PaymentRequest {
        address padAddress;
        address payeeBankAccount;
        uint256 paymentAmount;
        string executionDate;
        bool debitSuccessful;
        bool creditSuccessful;
    }
    
    // Mappings of address to above defined structs.
    mapping(address => Party) parties;
    mapping(address => BankAccount) bankAccounts;
    mapping(address => Bank) banks;
    mapping(address => PADAgreementForm) pads;
    mapping(address => PaymentRequest) paymentRequests;

    // Constructor.
    constructor() public {
        developer = msg.sender;
    }

    // Represents the onboarding of banks on the platform by the developer.
    // Only the developer can execute this function.
    modifier onlyDeveloper() {
        require(msg.sender == developer, "Sender not authorized.");
        _;
    }

    function createBank(address _address, string _name, string _businessNumber) public onlyDeveloper {
        banks[_address].name = _name;
        banks[_address].businessNumber = _businessNumber;
        banks[_address].isBank = true;
    }
    
    // Fetch details of bank. All roles can view details.
    function getBankDetails(address _bankAddress) public view returns(string, string) {
        return (banks[_bankAddress].name, banks[_bankAddress].businessNumber);
    }
    
    // Function that initializes BankAccount. Only banks can create these accounts.
    // Bank accounts are only opened when banks have identified the party's identity off-chain.
    modifier onlyBank() {
        require(banks[msg.sender].isBank, "Sender not authorized.");
        _;
    }

    modifier onlyBankOrOwner(address _accountAddress) {
        require
        (
            bankAccounts[_accountAddress].bank == msg.sender || 
            bankAccounts[_accountAddress].owner == msg.sender,
            "Sender not authorized."
        );
        _;
    }
    
    function createBankAccount
    (
        address _ownerAddress,  // Party address.
        // The below parameters are assigned by the bank. acctAddress is assigned off-chain.
        address _acctAddress, 
        string _transitNumber,
        string _institutionNumber,
        string _accountNumber
    )
        public
        onlyBank
    {
        //bankAccounts[_acctAddress].isOpen = false; false is default
        bankAccounts[_acctAddress].owner = _ownerAddress;
        bankAccounts[_acctAddress].bank = msg.sender;
        bankAccounts[_acctAddress].transitNumber = _transitNumber;
        bankAccounts[_acctAddress].institutionNumber = _institutionNumber;
        bankAccounts[_acctAddress].accountNumber = _accountNumber;
        
    }
    
    function getBankAccountDetails(address _accountAddress) 
        public 
        view 
        returns(
            bool, 
            string, 
            string, 
            string, 
            string, 
            string
        ) 
    {
        if 
        (
            bankAccounts[_accountAddress].bank == msg.sender || 
            bankAccounts[_accountAddress].owner == msg.sender
        )
            return 
            (
                bankAccounts[_accountAddress].isOpen, 
                parties[bankAccounts[_accountAddress].owner].name,
                banks[bankAccounts[_accountAddress].bank].name,
                bankAccounts[_accountAddress].transitNumber,
                bankAccounts[_accountAddress].institutionNumber,
                bankAccounts[_accountAddress].accountNumber          
            );  
    }

    // Anyone can create party but only banks can verify identities.
    function setParty(address _address, string name) public {
        parties[_address].name = name;
    }

    // Given identification verification off-chain by bank, set idVerified to true.
    function verifyIdentity(address _address) public onlyBank {
        parties[_address].idVerified = true;
    }

    // Officially open bank account given id verification by bank.
    function openBankAccount(address _acctAddress) public onlyBank {
        if (parties[bankAccounts[_acctAddress].owner].idVerified)
            bankAccounts[_acctAddress].isOpen = true;
    }
    
    // Close bank account.
    function closeBankAccount(address _acctAddress) public onlyBank {
        bankAccounts[_acctAddress].isOpen = false;
    }
    
    modifier onlyBankAccountOwner(address _address) {
        require(msg.sender == bankAccounts[_address].owner, "Sender not authorized.");
        _;
    }

    // Create PAD agreement.
    function fillPADAgreementForm
    (
        address _payorAddress,
        address _padAddress,  // Assigned by front-end API. New random address.
        address _payorBankAccount,
        address _payeeAddress,  // Party address of payee.
        PaymentType _paymentType,
        PaymentFrequency _paymentFrequency,
        string _expiryDate,
        uint256 _maxPaymentAmount,
        bool _isAuthorized
    ) 
        public 
        onlyBankAccountOwner(_payorBankAccount)
    {
        // Only fill if Payor is owner of the bank account.
        if (msg.sender == bankAccounts[_payorBankAccount].owner) {
            pads[_padAddress].payorAddress = _payorAddress;
            pads[_padAddress].payorBankAccount = _payorBankAccount;
            pads[_padAddress].payeeAddress = _payeeAddress;
            pads[_padAddress].expiryDate = _expiryDate;
            pads[_padAddress].paymentType = _paymentType;
            pads[_padAddress].paymentFrequency = _paymentFrequency;
            if (_isAuthorized)
                pads[_padAddress].isAuthorized = _isAuthorized;
            if (_paymentType != PaymentType.Unlimited)
                pads[_padAddress].maxPaymentAmount = _maxPaymentAmount;
        }
    }

    // View PAD details. Only payor, payee, and payor's bank can view. 
    function getPADDetails(address _padAddress) public view returns (
        address, 
        address, 
        PaymentType, 
        PaymentFrequency, 
        string, 
        uint256, 
        bool
    ) {
        if (
            msg.sender == pads[_padAddress].payorAddress ||
            msg.sender == pads[_padAddress].payeeAddress ||
            msg.sender == bankAccounts[pads[_padAddress].payorBankAccount].bank
        ) {
            return
        (
            // Payor account address is exposed to Payee, however cannot view details.
            // Trust in system is established in fillPADAgreementForm(). 
            // PAD form cannot be completed if payor is not owner of the bank account.
            pads[_padAddress].payorBankAccount,
            pads[_padAddress].payeeAddress,
            pads[_padAddress].paymentType,
            pads[_padAddress].paymentFrequency,
            pads[_padAddress].expiryDate,
            pads[_padAddress].maxPaymentAmount,
            pads[_padAddress].isAuthorized
        );
        }
    }

    // Used by payee or bank to check identity of payor account holder.
    // getPADDetails() can only return 7 variables.
    modifier onlyPADParties(address _padAddress) {
        require(msg.sender == pads[_padAddress].payorAddress ||
            msg.sender == pads[_padAddress].payeeAddress ||
            msg.sender == bankAccounts[pads[_padAddress].payorBankAccount].bank, 
            "Sender not authorized."
        );
        _;
    }

    // Required by both payee and bank.
    function getPayorAddress (address _padAddress) public view onlyPADParties(_padAddress) returns (address) {
        return (pads[_padAddress].payorAddress);
    }

    // Only payee can produce payment request.
    // Payment request address to be provided to payor and payee banks off-chain.
    // Payee's bank account must belong to payee for payment to be processed.
    // It is assumed that banks consume paymentType, paymentFrequency, and expiryDate off-chain as a
    // requirement to approve payments. Ideally, a datetime comparison of current and expiry time would happen here.
    modifier onlyPayee(address _address) {
        require(msg.sender == pads[_address].payeeAddress, "Sender not authorized.");
        _;
    }

    modifier ensurePADAuthorization(address _address) {
        require(pads[_address].isAuthorized, "Sender not authorized.");
        _;
    }

    function processPayment 
    (
        address _paymentAddress,
        address _padAddress, 
        address _payeeBankAccount,
        uint256 _paymentAmount, 
        string _executionDate
    ) 
        public 
        onlyPayee(_padAddress)
        ensurePADAuthorization(_padAddress)
    {
        if (msg.sender == bankAccounts[_payeeBankAccount].owner) {
            paymentRequests[_paymentAddress].padAddress = _padAddress;
            paymentRequests[_paymentAddress].payeeBankAccount = _payeeBankAccount;
            paymentRequests[_paymentAddress].paymentAmount = _paymentAmount;
            paymentRequests[_paymentAddress].executionDate = _executionDate;
        }
    }


}