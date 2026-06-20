// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../src/interfaces/IDefense.sol";

/// @title Submission — drop YOUR defense here and get scored (no registry edits).
/// @notice Replace the body of `authorize` with your defense, then run:
///         `make submit`  (or `cd aegis-gym && python3 -m aegis submit reentrancy`).
///         The harness scores this contract on the reentrancy scenario's full
///         attacker grid + benign suite and tells you your worst-case reward and
///         where you'd rank. This is the local form of the hosted "submit a
///         defense, get scored, climb the board" loop.
///
///         The reentrancy scenario passes ctx = abi.encode(recordedBalance,
///         vaultBalance). The default below is the per-address, per-transaction
///         balance invariant (a perfect-scoring reference) — beat it, or match it
///         by a different mechanism.
contract Submission is IDefense {
    function authorize(address caller, bytes4, uint256 value, bytes calldata ctx)
        external
        returns (bool)
    {
        (uint256 recordedBalance, ) = abi.decode(ctx, (uint256, uint256));
        bytes32 slot = keccak256(abi.encode("aegis.submission.cum", caller));
        uint256 cum;
        assembly {
            cum := tload(slot)
        }
        cum += value;
        assembly {
            tstore(slot, cum)
        }
        return cum <= recordedBalance;
    }
}
