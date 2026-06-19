// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../../interfaces/IDefense.sol";

/// @title VulnerableVault — Scenario 01 target.
/// @notice A deliberately vulnerable ETH vault (classic reentrancy: the
///         external call happens BEFORE the balance is updated). The ONLY
///         security-relevant addition a real protocol makes is the single
///         `authorize` firewall-hook line inside `withdraw`. Everything else
///         is left intentionally exploitable so that the defense — not the
///         target — is what gets scored.
contract VulnerableVault {
    mapping(address => uint256) public balances;
    IDefense public immutable defense;

    constructor(IDefense _defense) {
        defense = _defense;
    }

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "insufficient");

        // ---- Aegis firewall hook (the one line a protocol integrates) ----
        if (address(defense) != address(0)) {
            bool allow = defense.authorize(
                msg.sender,
                msg.sig,
                amount,
                abi.encode(balances[msg.sender], address(this).balance)
            );
            require(allow, "AEGIS_BLOCKED");
        }
        // ------------------------------------------------------------------

        // VULNERABLE: interaction precedes effects.
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "transfer failed");

        // `unchecked` models the classic (pre-0.8 / unchecked-math) drainable
        // bug: with effects after interaction, the attacker re-enters before
        // this line runs, so the per-user check above always passes.
        unchecked {
            balances[msg.sender] -= amount;
        }
    }

    function totalAssets() external view returns (uint256) {
        return address(this).balance;
    }

    receive() external payable {}
}
