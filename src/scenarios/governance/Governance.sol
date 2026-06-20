// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../../interfaces/IDefense.sol";
import {GovToken} from "./GovToken.sol";

/// @title Governance — Scenario 04 target (flash-loan governance takeover).
/// @notice A treasury-controlling governor that counts votes at the CURRENT
///         token balance (the bug). Because voting power can be flash-borrowed
///         within a single transaction, an attacker can mint enough tokens to
///         clear quorum, execute a treasury drain, and repay — all atomically
///         (the Beanstalk class). The one-line Aegis hook lets a defense inspect
///         both current and start-of-block (prior) voting power.
///
///         ctx = abi.encode(priorVotes, currentVotes). A vote-count threshold
///         cannot tell a flash-borrowed quorum from a legitimately held one (the
///         two are identical by count); a snapshot defense that requires votes to
///         be backed by prior holdings stops any single-block flash loan.
contract Governance {
    GovToken public immutable token;
    IDefense public immutable defense;
    uint256 public immutable quorum;

    constructor(GovToken _token, IDefense _defense, uint256 _quorum) payable {
        token = _token;
        defense = _defense;
        quorum = _quorum;
    }

    /// Execute a passed proposal: move `amount` from the treasury to `to`,
    /// authorized by `votes` voting power held by the caller.
    function execute(uint256 votes, address to, uint256 amount) external {
        // ---- Aegis firewall hook ----
        if (address(defense) != address(0)) {
            bool allow = defense.authorize(
                msg.sender,
                msg.sig,
                votes,
                abi.encode(token.priorVotes(msg.sender), token.balanceOf(msg.sender))
            );
            require(allow, "AEGIS_BLOCKED");
        }
        // -----------------------------

        // VULNERABLE: voting power is read at the current balance, which a
        // flash loan can inflate within this very transaction.
        require(votes <= token.balanceOf(msg.sender), "insufficient votes");
        require(votes >= quorum, "below quorum");
        require(amount <= address(this).balance, "insufficient funds");

        (bool ok, ) = to.call{value: amount}("");
        require(ok, "transfer failed");
    }

    function totalAssets() external view returns (uint256) {
        return address(this).balance;
    }

    receive() external payable {}
}
