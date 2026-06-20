// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../../interfaces/IDefense.sol";

/// @title SmartAccount — Scenario 05 target (stolen-key drain; no clean invariant).
/// @notice A wallet whose withdrawals are gated by the canonical authorization
///         invariant `msg.sender == owner` — the exact structural defense that
///         WINS Scenario 03. Here it is useless: the attacker has stolen the
///         owner's key, so it passes the check and drains the account. There is
///         no structural invariant that separates the thief from the owner,
///         because by every on-chain authorization the thief *is* the owner.
///
///         The only signal is BEHAVIORAL, and it is deliberately ambiguous: a
///         legitimate owner sometimes makes a large withdrawal, and sometimes
///         pays a brand-new address — and a patient thief can mimic exactly that.
///         So unlike every other Aegis scenario, no defense can reach perfect
///         recall at zero false positives. The result is a precision/recall
///         FRONTIER, and a defense that combines features (a learned classifier)
///         dominates single-feature thresholds — but cannot erase the overlap.
///
///         ctx = abi.encode(amount, isNewDestination). `value` == amount.
contract SmartAccount {
    IDefense public immutable defense;
    address public immutable owner;
    mapping(address => bool) public known; // destinations the owner has used before

    constructor(IDefense _defense, address _owner) payable {
        defense = _defense;
        owner = _owner;
    }

    function markKnown(address dest) external {
        known[dest] = true;
    }

    function withdraw(uint256 amount, address to) external {
        // The authorization invariant — and the attacker passes it (stolen key).
        require(msg.sender == owner, "not owner");

        bool isNew = !known[to];
        if (address(defense) != address(0)) {
            bool allow = defense.authorize(msg.sender, msg.sig, amount, abi.encode(amount, isNew));
            require(allow, "AEGIS_BLOCKED");
        }

        (bool ok, ) = to.call{value: amount}("");
        require(ok, "transfer failed");
    }

    receive() external payable {}
}
