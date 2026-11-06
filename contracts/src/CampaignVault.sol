// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title CampaignVault
/// @notice Brands lock a budget in the native token (0G testnet). The operator settles
/// impressions to verified pets. Unspent budget refunds to the brand after the end time.
/// The pet's own key can never change where its money goes; only the human owner can.
contract CampaignVault {
    struct Campaign {
        address brand;
        uint128 budget;
        uint128 spent;
        uint96 rate; // paid per impression, in wei
        uint64 endTime;
        bool closed;
        bytes32 lineHash; // hash of the ad line text, stored off chain
    }

    struct Pet {
        address owner; // the World-verified human
        address payout; // where earnings go (normally the pet's wallet)
        bool verified; // set by the operator after a backend World ID check
    }

    /// @notice After endTime the operator has this long to settle the last impressions.
    /// The campaign can only be closed (and refunded) once it has passed.
    uint256 public constant SETTLE_GRACE = 1 hours;

    address public admin;
    address public operator;
    uint256 public nextCampaignId = 1;

    mapping(uint256 => Campaign) public campaigns;
    mapping(address => Pet) public pets; // keyed by the pet's own key address

    bool private locked;

    event CampaignCreated(uint256 indexed id, address indexed brand, uint256 budget, uint256 rate, uint64 endTime, bytes32 lineHash);
    event CampaignToppedUp(uint256 indexed id, uint256 amount, uint256 newBudget);
    event ImpressionsSettled(uint256 indexed id, address indexed pet, address indexed payout, uint256 count, uint256 amount);
    event CampaignClosed(uint256 indexed id, uint256 refund);
    event PetRegistered(address indexed pet, address indexed owner, address payout);
    event PetVerified(address indexed pet, bool verified);
    event PayoutChanged(address indexed pet, address payout);
    event OperatorChanged(address operator);

    error NotAdmin();
    error NotOperator();
    error NotBrand();
    error NotPetOwner();
    error BadParams();
    error UnknownCampaign();
    error CampaignIsClosed();
    error CampaignEnded();
    error CampaignNotEnded();
    error PetNotVerified();
    error OverBudget();
    error TransferFailed();
    error Reentrancy();

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    modifier onlyOperator() {
        if (msg.sender != operator) revert NotOperator();
        _;
    }

    modifier nonReentrant() {
        if (locked) revert Reentrancy();
        locked = true;
        _;
        locked = false;
    }

    constructor(address operator_) {
        if (operator_ == address(0)) revert BadParams();
        admin = msg.sender;
        operator = operator_;
    }

    function setOperator(address operator_) external onlyAdmin {
        if (operator_ == address(0)) revert BadParams();
        operator = operator_;
        emit OperatorChanged(operator_);
    }

    // ---------- pets ----------

    /// @notice Called by the backend after it has checked the owner's World ID proof.
    function registerPet(address pet, address owner, address payout) external onlyOperator {
        if (pet == address(0) || owner == address(0) || payout == address(0)) revert BadParams();
        if (pets[pet].owner != address(0)) revert BadParams(); // one registration per pet key
        pets[pet] = Pet({owner: owner, payout: payout, verified: true});
        emit PetRegistered(pet, owner, payout);
        emit PetVerified(pet, true);
    }

    function setVerified(address pet, bool verified) external onlyOperator {
        if (pets[pet].owner == address(0)) revert BadParams();
        pets[pet].verified = verified;
        emit PetVerified(pet, verified);
    }

    /// @notice Only the human owner can redirect earnings. The pet key cannot.
    function setPayout(address pet, address payout) external {
        if (msg.sender != pets[pet].owner) revert NotPetOwner();
        if (payout == address(0)) revert BadParams();
        pets[pet].payout = payout;
        emit PayoutChanged(pet, payout);
    }

    // ---------- campaigns ----------

    function createCampaign(bytes32 lineHash, uint96 rate, uint64 endTime) external payable returns (uint256 id) {
        if (rate == 0 || endTime <= block.timestamp || msg.value < rate || msg.value > type(uint128).max) {
            revert BadParams();
        }
        id = nextCampaignId++;
        campaigns[id] = Campaign({
            brand: msg.sender,
            budget: uint128(msg.value),
            spent: 0,
            rate: rate,
            endTime: endTime,
            closed: false,
            lineHash: lineHash
        });
        emit CampaignCreated(id, msg.sender, msg.value, rate, endTime, lineHash);
    }

    function topUp(uint256 id) external payable {
        Campaign storage c = _live(id);
        if (msg.sender != c.brand) revert NotBrand();
        if (block.timestamp > c.endTime) revert CampaignEnded();
        uint256 newBudget = uint256(c.budget) + msg.value;
        if (msg.value == 0 || newBudget > type(uint128).max) revert BadParams();
        c.budget = uint128(newBudget);
        emit CampaignToppedUp(id, msg.value, newBudget);
    }

    function settleImpressions(uint256 id, address pet, uint256 count) external onlyOperator nonReentrant {
        Campaign storage c = _live(id);
        if (block.timestamp > uint256(c.endTime) + SETTLE_GRACE) revert CampaignEnded();
        Pet memory p = pets[pet];
        if (!p.verified) revert PetNotVerified();
        if (count == 0) revert BadParams();
        uint256 amount = count * c.rate;
        if (uint256(c.spent) + amount > c.budget) revert OverBudget();
        c.spent += uint128(amount);
        emit ImpressionsSettled(id, pet, p.payout, count, amount);
        _send(p.payout, amount);
    }

    function close(uint256 id) external nonReentrant {
        Campaign storage c = _live(id);
        if (block.timestamp <= uint256(c.endTime) + SETTLE_GRACE) revert CampaignNotEnded();
        c.closed = true;
        uint256 refund = uint256(c.budget) - c.spent;
        emit CampaignClosed(id, refund);
        if (refund > 0) _send(c.brand, refund);
    }

    function remaining(uint256 id) external view returns (uint256) {
        Campaign storage c = campaigns[id];
        if (c.closed) return 0;
        return uint256(c.budget) - c.spent;
    }

    // ---------- internal ----------

    function _live(uint256 id) internal view returns (Campaign storage c) {
        c = campaigns[id];
        if (c.brand == address(0)) revert UnknownCampaign();
        if (c.closed) revert CampaignIsClosed();
    }

    function _send(address to, uint256 amount) internal {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
