// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "./interfaces/IDefense.sol";

/// @title CircuitBreaker — the installable, real-time firewall a protocol deploys.
/// @notice This is the on-chain half of Aegis Sentinel: the piece a protocol drops
///         into its contracts TODAY. A sensitive function calls `check()` (or the
///         `whenLive` modifier pattern) and reverts when the breaker is tripped.
///         Off-chain, the Aegis keeper watches the protocol's oracle on live
///         mainnet and calls `trip()` the instant it detects manipulation — pausing
///         the market in one block, before a borrow/liquidation can execute against
///         a manipulated price.
///
///         Design principles (defensive, bounded, reversible):
///         - The breaker can ONLY pause; it never moves funds or changes logic.
///         - `trip()` is callable by any authorized guardian (the keeper, a
///           multisig, or an on-chain `IDefense` auto-trip) — fast to stop harm.
///         - `reset()` requires `owner` (governance) — slow, deliberate restart.
///         - An optional `IDefense` lets the protocol auto-trip from on-chain
///           evidence (e.g. a price-deviation guard) without waiting for the keeper.
contract CircuitBreaker {
    address public owner;                  // governance: can reset and manage guardians
    mapping(address => bool) public guardian; // fast responders that may trip
    bool public tripped;
    string public reason;
    uint256 public trippedAt;

    IDefense public autoTrip;              // optional: on-chain auto-trip evidence

    event Tripped(address indexed by, string reason);
    event Reset(address indexed by);
    event GuardianSet(address indexed who, bool allowed);
    event AutoTripSet(address indexed defense);

    error Paused();
    error NotOwner();
    error NotGuardian();

    constructor(address[] memory guardians) {
        owner = msg.sender;
        for (uint256 i = 0; i < guardians.length; i++) {
            guardian[guardians[i]] = true;
            emit GuardianSet(guardians[i], true);
        }
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @notice Protocols call this at the top of a protected action; it reverts
    ///         when the market is paused. (Or wrap logic with `whenLive`.)
    function check() public view {
        if (tripped) revert Paused();
    }

    modifier whenLive() {
        if (tripped) revert Paused();
        _;
    }

    /// @notice Pause the protocol. Callable by any guardian (the keeper/multisig).
    function trip(string calldata why) external {
        if (!guardian[msg.sender] && msg.sender != owner) revert NotGuardian();
        _trip(why);
    }

    /// @notice Auto-trip from on-chain evidence: if the configured defense would
    ///         BLOCK the supplied context (i.e. detects manipulation), anyone may
    ///         trip the breaker — no trusted keeper required for this path.
    function autoTripWith(bytes calldata ctx) external {
        require(address(autoTrip) != address(0), "no auto-trip set");
        bool allow = autoTrip.authorize(msg.sender, msg.sig, 0, ctx);
        require(!allow, "defense allows: no manipulation");
        _trip("auto-trip: on-chain defense flagged manipulation");
    }

    function _trip(string memory why) internal {
        if (!tripped) {
            tripped = true;
            reason = why;
            trippedAt = block.number;
            emit Tripped(msg.sender, why);
        }
    }

    /// @notice Restart the market — deliberate, governance-only.
    function reset() external onlyOwner {
        tripped = false;
        reason = "";
        emit Reset(msg.sender);
    }

    function setGuardian(address who, bool allowed) external onlyOwner {
        guardian[who] = allowed;
        emit GuardianSet(who, allowed);
    }

    function setAutoTrip(IDefense defense) external onlyOwner {
        autoTrip = defense;
        emit AutoTripSet(address(defense));
    }

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }
}
