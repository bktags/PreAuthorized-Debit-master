pragma solidity ^0.4.21;
contract DateTime {
        function getYear(uint timestamp) public constant returns (uint16);
        function getMonth(uint timestamp) public constant returns (uint8);
        function getDay(uint timestamp) public constant returns (uint8);
        function isLeapYear(uint16 year) public constant returns (bool);
}

contract PreAuthorizedDebit {
    //address public dateTimeAddr = 0x8Fc065565E3e44aef229F1D06aac009D6A524e82;
    address public dateTimeAddr = 0x1a6184CD4C5Bea62B0116de7962EE7315B7bcBce;
    DateTime dateTime = DateTime(dateTimeAddr);

    address private owner;      // The bank owning and deploying the contract.

    //Payee is the service provider that can be authorized for debiting a payee account.
    struct PADPayee {
        string businessNumber;
        DebitAuthorization[] accreditedPADs;
    }
    mapping(address => PADPayee) private registeredPayees;
    address[] private payeeList;

    // Payor is the initiator for setting up a preAuthorized debit.
    struct PADPayor {
        address[] activePayeeList;      // the list of payees for which the payor has PADs

        // key for this mapping is the payee address, maps to a PAD agreement with that payee.
        // Currently allows only one PAD per payee.
        // Future expansion as an array to allow multiple PADs against a single payee.
        mapping(address => DebitAuthorization) activePADs;
        mapping(address => FulfilledPAD[]) historicalDebits;    //key is payee address
    }
    mapping(address => PADPayor) private registeredPayors;
    address[] private payorList;

    struct DebitAuthorization {
        address payor;
        uint PAD_Id;            // unique identifier assigned to each PAD agreement.
        address authorizedPayee;
        uint amount;
        DebitPaymentType paymentType;
        DebitFrequencyType debitFrequency;
        uint32 startDate;
        uint32 endDate;
        uint32 nextPaymentDueDate;
    }
    
    // Contains a record of past fullfilled debits, captured on the occurrence of each cycle of a scheduled debit agreement.
    struct FulfilledPAD {
        uint PAD_ID;
        address payor;
        address authorizedPayee;
        uint amount;
        uint fulfillmentDate;     // Date the debit became due per PAD schedule.
    }

    enum DebitPaymentType {Fixed, Variable}
    enum DebitFrequencyType {Daily, Weekly, BiWeekly, Monthly, Annual, Sporadic}
    DebitPaymentType constant defaultDebitPayment = DebitPaymentType.Fixed;
    DebitFrequencyType constant defaultDebitFrequency = DebitFrequencyType.Monthly;

    function getDefaultDebitPayment() pure public returns (uint8) {
        return uint8(defaultDebitPayment);
    }
    
    function getDefaultDebitFrequency() pure public returns (uint8) {
        return uint8(defaultDebitFrequency);
    }
    
    // Contract Constructor
    // Setup/initiated by bank supporting consumer initiated PAD agreements.
    constructor() public {
        owner = msg.sender;
    }

    //Our fallback function for error processing. For now we implement the default behaviour
    //as if no fallback had been provided.
    // function () public {
    // }

    modifier onlyOwner() {
        require(owner == msg.sender);
        _;
    }
    modifier isRegisteredPayee(address payee) {
        //Either loop through payeeList array to check if it contains address supplied, or,
        //check the mapped struct contains a valid business number.
        require((keccak256(registeredPayees[payee].businessNumber) != keccak256("")), "Not a valid registered payee.");
        _;
    }

    modifier isValidPaymentType(uint8 _paymentType) {
        require(uint8(DebitPaymentType.Variable) >= _paymentType, "Not a valid payment type. Must be fixed or variable.");
        _;
    }

    modifier isValidFrequencyType(uint8 _frequency) {
        require(uint8(DebitFrequencyType.Sporadic) >= _frequency, "Not a valid frequency for payment.");
        _;
    }

    modifier hasPADAgreement(address _payee, address _payor) {
        require(registeredPayors[_payor].activePADs[_payee].authorizedPayee == _payee);
        _;
    }

    // Adds a Payee as a selectable entity against which PADs can be defined.
    // At this time we only allow contract deployer (the bank) to register valid payees.
    // This could change in the future for payees to self-register dependent on validation provisos being met.
    function registerPayee(address payeeAddress, string uniqueBusinessId) onlyOwner() public returns (bool) {

        // Only register if new payee
        if (keccak256(registeredPayees[payeeAddress].businessNumber) != keccak256("") && 
            keccak256(registeredPayees[payeeAddress].businessNumber) != keccak256(uniqueBusinessId)) {
            return false;
        }

        registeredPayees[payeeAddress].businessNumber = uniqueBusinessId;
        payeeList.push(payeeAddress);
        return true;
    }

    // A payor is not needed to be explicityly registered. The first PAD creation will create the payor object

    function getRegisteredPayees() view public returns (address[]) {
        return payeeList;
    }

    function getRegisteredPayors() view public returns (address[]) {
        return payorList;
    }

    function addDebitAuthorization(
            address _payor,
            uint _PAD_Id,
            address _payee,
            uint _amount,
            uint8 _paymentType,
            uint8 _frequency,
            uint32 _startdate,uint32 _enddate)
            isRegisteredPayee(_payee)
            isValidPaymentType(_paymentType)
            isValidFrequencyType(_frequency) public returns (bool result) {
        
        DebitAuthorization memory newPAD;
        newPAD.PAD_Id = _PAD_Id;
        newPAD.payor = _payor;
        newPAD.authorizedPayee = _payee;
        newPAD.paymentType = DebitPaymentType(_paymentType);
        newPAD.debitFrequency = DebitFrequencyType(_frequency);
        newPAD.amount = _amount;
        newPAD.startDate = _startdate;
        newPAD.endDate = _enddate;
        newPAD.nextPaymentDueDate = _startdate;

        registeredPayors[_payor] = PADPayor(new address[](0));
        registeredPayors[_payor].activePayeeList.push(_payee);
        registeredPayors[_payor].activePADs[_payee] = newPAD;

        payorList.push(_payor);
        // Now also update the payee with the new PAD.
        registeredPayees[_payee].accreditedPADs.push(newPAD);
        return true;
    }

    // For PAD agreements with variable payment amounts, payee will add a transaction that defines the amount
    // owed and the date payable. This is equivalent to the payee sending a bill/invoice to the payor for 
    // amounts owed. This can be updated at any time until the day of payment.
    function updatePaymentOwed(address _payor, uint _amountOwed, uint32 _dueDate)
                 isRegisteredPayee(msg.sender)
                 hasPADAgreement(msg.sender, _payor) public returns (bool) {
        require(registeredPayors[_payor].activePADs[msg.sender].paymentType == DebitPaymentType.Variable);
        require(registeredPayors[_payor].activePADs[msg.sender].nextPaymentDueDate <= _dueDate);
        require(_dueDate > now);

        registeredPayors[_payor].activePADs[msg.sender].amount = _amountOwed;
        registeredPayors[_payor].activePADs[msg.sender].nextPaymentDueDate = _dueDate;
        return true;
    }
        
    event NewScheduledPADPayment (
        uint PAD_Id,
        address indexed payee,
        address indexed payor,
        uint paymentAmount
    );

    // Executed on the scheduled date of a PAD. This function runs as an external call.
    // At this time Solidity does not include delayed calling or timers to enable scheduling of events.
    // Processing a PAD agreement means journalising an immutable record of the payment on the due date.
     function executeDebitPayment(address _payee, uint _PAD_Id, address _payor) 
                            isRegisteredPayee(_payee)
                            hasPADAgreement(_payee, _payor) public returns (bool) {
        require(registeredPayors[_payor].activePADs[_payee].PAD_Id == _PAD_Id);

        FulfilledPAD memory journaledPAD;
        journaledPAD.PAD_ID = _PAD_Id;
        journaledPAD.payor = _payor;
        journaledPAD.authorizedPayee = _payee;
        journaledPAD.amount = registeredPayors[_payor].activePADs[_payee].amount;
        journaledPAD.fulfillmentDate = now;

        registeredPayors[_payor].historicalDebits[_payee].push(journaledPAD);
        updateNextDueDate(registeredPayors[_payor].activePADs[_payee]);

        emit NewScheduledPADPayment(_PAD_Id, _payee, _payor, journaledPAD.amount);
        return true;
     }

    // This function will update the next scheduled date expected for a PAD payment.
    function updateNextDueDate(DebitAuthorization storage _pad) internal {
        if (_pad.debitFrequency == DebitFrequencyType.Daily) {
            _pad.nextPaymentDueDate = uint32(now) + 1 days;
        } else if (_pad.debitFrequency == DebitFrequencyType.Weekly) {
            _pad.nextPaymentDueDate = uint32(now) + 7 days;
        } else if (_pad.debitFrequency == DebitFrequencyType.BiWeekly) {
            _pad.nextPaymentDueDate = uint32(now) + 14 days;
        } else if (_pad.debitFrequency == DebitFrequencyType.Monthly) {
            _pad.nextPaymentDueDate = uint32(now) +  30 days;
        } else if (_pad.debitFrequency == DebitFrequencyType.Annual) {
            _pad.nextPaymentDueDate = uint32(now) + 365 days + 
                                        (dateTime.isLeapYear(dateTime.getYear(now)) ? 1 days : 0 days);
        } 
    }

    // Function to allow a payor or payee to view their own PAD agreements. 
    // Future: return a list of PADs setup up by the provided payor address
    function getPADAuthorization(address _payor, uint _PAD_Id, address _payee) view public
             returns (uint8, uint8, uint, uint32, uint32, uint32) {
        require(_payor == msg.sender || _payee == msg.sender || owner == msg.sender);
        require(registeredPayors[_payor].activePADs[_payee].PAD_Id == _PAD_Id);

        DebitAuthorization storage pad = registeredPayors[_payor].activePADs[_payee];

        return (uint8(pad.paymentType),
                uint8(pad.debitFrequency),
                pad.amount,
                pad.startDate,
                pad.endDate,
                pad.nextPaymentDueDate);
    }
}