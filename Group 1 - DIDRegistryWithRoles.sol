// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract DIDTicketingDApp {
    struct DID {
        string identifier; // Unique identifier for the DID
        address owner; // address of the DID owner
        uint256 createdAt; // Timestamp of DID creation
    }

    struct MetaData {
        string name;
        string email;
        string profilePicture;
    }

    struct Credential {
        address issuer;
        string role;
        uint256 issueAt;
        bytes32 hashes;
    }

    struct Event {
        string name; // Name of the event
        uint256 totalSupply; // Total number of tickets available
        uint256 availableTickets; // Current number of tickets remaining
        uint256 price; // Price per ticket
        uint256 eventDate; // Timestamp of the event
        address organizer; // Address of event organizer
        bool isActive; // Whether the event is active or cancelled
    }

    struct Ticket {
        uint256 eventId;
        address owner;
        bool isValid;
        uint256 purchaseDate;
    }

    enum Role {
        NONE,
        USER,
        ORGANIZER,
        SUPER_ADMIN
    }

    // Function to convert Role enum to string
    function getRoleString(Role _role) internal pure returns (string memory) {
        if (_role == Role.SUPER_ADMIN) return "super admin";
        if (_role == Role.ORGANIZER) return "organizer";
        if (_role == Role.USER) return "user";
        return "none";
    }

    // Important state variables
    mapping(address => DID) private dids; // Maps addresses to their DIDs
    mapping(address => Role) private roles;
    mapping(address => Role[]) private roleHistory; // Tracks role history for each address
    mapping(address => MetaData) private metadatas;
    mapping(address => Credential[]) private credentials;

    // New mappings for ticketing
    mapping(uint256 => Event) private events; // Maps eventId to Event details
    mapping(uint256 => Ticket) private tickets; // Maps ticketId to Ticket details
    mapping(address => uint256[]) private userTickets; // Maps user addresses to their ticket IDs

    uint256 private nextEventId = 1;
    uint256 private nextTicketId = 1;

    constructor() {
        roles[msg.sender] = Role.SUPER_ADMIN;
        roleHistory[msg.sender].push(Role.SUPER_ADMIN);
    }

    // Original events
    event DIDCreated(address indexed owner, string identifier);
    event SetMetaData(
        address indexed owner,
        string name,
        string email,
        string profilePicture
    );
    event RoleAssign(address indexed user, string role);
    event RoleIssued(
        address indexed user,
        address receiver,
        string role,
        bytes32 hash
    );

    // Add Super Admin modifier
    modifier onlySuperAdmin() {
        require(
            roles[msg.sender] == Role.SUPER_ADMIN,
            "Only super admin can perform this action"
        );
        _;
    }

    // Update the functions with the modifier
    function assignRole(address _user, Role _role) public onlySuperAdmin {
        require(_user != address(0), "Invalid address");
        require(dids[msg.sender].owner != address(0), "Issuer must have a DID");
        require(_role != Role.NONE, "Role cannot be NONE");
        roles[_user] = _role;
        roleHistory[_user].push(_role);
        emit RoleAssign(_user, getRoleString(_role));
    }

    function issueRole(address _user, Role _role) public onlySuperAdmin {
        require(dids[msg.sender].owner != address(0), "Issuer must have a DID");
        require(_role != Role.NONE, "Role cannot be NONE");

        bytes32 roleHash = keccak256(
            abi.encodePacked(msg.sender, _user, _role, block.timestamp)
        );
        credentials[_user].push(
            Credential(
                msg.sender,
                getRoleString(_role),
                block.timestamp,
                roleHash
            )
        );
        roleHistory[_user].push(_role);
        emit RoleIssued(msg.sender, _user, getRoleString(_role), roleHash);
    }

    function createDID(string memory _identifier) public {
        require(bytes(_identifier).length > 0, "Identifier cannot be empty");
        require(dids[msg.sender].owner == address(0), "DID already exists");
        dids[msg.sender] = DID(_identifier, msg.sender, block.timestamp);
        emit DIDCreated(msg.sender, _identifier);
    }

    function getDID() public view returns (string memory) {
        require(
            dids[msg.sender].owner != address(0),
            "No DID found for this address"
        );

        return dids[msg.sender].identifier;
    }

    function setMetadata(
        string memory name,
        string memory email,
        string memory profilePicture
    ) public {
        require(bytes(name).length > 0, "Name cannot be empty");
        require(bytes(email).length > 0, "Email cannot be empty");
        require(
            bytes(profilePicture).length > 0,
            "Profile picture cannot be empty"
        );
        require(
            dids[msg.sender].owner != address(0),
            "No DID found for this address"
        );
        metadatas[msg.sender] = MetaData(name, email, profilePicture);
        emit SetMetaData(msg.sender, name, email, profilePicture);
    }

    function getMetadata() public view returns (MetaData memory) {
        require(dids[msg.sender].owner != address(0), "Data does not exist");
        return metadatas[msg.sender];
    }

    function getRole() public view returns (string[] memory) {
        require(
            dids[msg.sender].owner != address(0),
            "No DID found for this address"
        );

        Role[] memory userRoles = roleHistory[msg.sender];
        require(userRoles.length > 0, "No roles found for this address");

        string[] memory roleStrings = new string[](userRoles.length);
        for (uint i = 0; i < userRoles.length; i++) {
            roleStrings[i] = getRoleString(userRoles[i]);
        }

        return roleStrings;
    }

    // New events for ticketing
    event EventCreated(uint256 indexed eventId, string name, address organizer);
    event TicketPurchased(
        uint256 indexed ticketId,
        uint256 indexed eventId,
        address buyer
    );
    event EventCancelled(uint256 indexed eventId);

    // New ticketing functions
    modifier onlyEventOrganizer(uint256 _eventId) {
        require(
            events[_eventId].organizer == msg.sender,
            "Not the event organizer"
        );
        _;
    }

    // Modifier to ensure user has a valid DID before performing actions
    modifier hasValidDID() {
        require(dids[msg.sender].owner != address(0), "Must have a valid DID");
        _;
    }

    // Add new modifier for organizer role
    modifier onlyOrganizer() {
        require(
            roles[msg.sender] == Role.ORGANIZER,
            "Only organizer can perform this action"
        );
        _;
    }

    // Update createEvent to require organizer role
    function createEvent(
        string memory _name,
        uint256 _totalSupply,
        uint256 _price,
        uint256 _eventDate
    ) public hasValidDID onlyOrganizer returns (uint256) {
        // Input validation
        require(_totalSupply > 0, "Total supply must be greater than 0");
        require(_price > 0, "Price must be greater than 0");
        require(
            _eventDate > block.timestamp,
            "Event date must be in the future"
        );

        // Create new event with unique ID
        uint256 eventId = nextEventId++;
        events[eventId] = Event({
            name: _name,
            totalSupply: _totalSupply,
            availableTickets: _totalSupply,
            price: _price,
            eventDate: _eventDate,
            organizer: msg.sender,
            isActive: true
        });

        emit EventCreated(eventId, _name, msg.sender);
        return eventId;
    }

    // Allows users to purchase tickets for an event
    function purchaseTicket(uint256 _eventId) public payable hasValidDID {
        Event storage event_ = events[_eventId];

        // Validate purchase conditions
        require(event_.isActive, "Event is not active");
        require(event_.availableTickets > 0, "No tickets available");
        require(msg.value >= event_.price, "Insufficient payment");

        // Create new ticket
        uint256 ticketId = nextTicketId++;
        tickets[ticketId] = Ticket({
            eventId: _eventId,
            owner: msg.sender,
            isValid: true,
            purchaseDate: block.timestamp
        });

        // Update event state and user tickets
        event_.availableTickets--;
        userTickets[msg.sender].push(ticketId);

        // Transfer payment to event organizer
        payable(event_.organizer).transfer(msg.value);

        emit TicketPurchased(ticketId, _eventId, msg.sender);
    }

    function getUserTickets()
        public
        view
        hasValidDID
        returns (uint256[] memory)
    {
        // Check if user has any tickets
        require(userTickets[msg.sender].length > 0, "User has no tickets");
        return userTickets[msg.sender];
    }

    function getTicketDetails(
        uint256 _ticketId
    ) public view returns (Ticket memory) {
        // Check if ticket exists by verifying if the owner address is not zero
        require(
            tickets[_ticketId].owner != address(0),
            "Ticket does not exist"
        );
        return tickets[_ticketId];
    }

    function getEventDetails(
        uint256 _eventId
    ) public view returns (Event memory) {
        // Check if event exists by verifying if the organizer address is not zero
        require(
            events[_eventId].organizer != address(0),
            "Event does not exist"
        );
        return events[_eventId];
    }

    // Update cancelEvent to require both organizer role and event ownership
    function cancelEvent(
        uint256 _eventId
    ) public onlyOrganizer onlyEventOrganizer(_eventId) {
        require(
            events[_eventId].organizer != address(0),
            "Event does not exist"
        );
        require(events[_eventId].isActive, "Event already cancelled");
        events[_eventId].isActive = false;
        emit EventCancelled(_eventId);
    }
}
