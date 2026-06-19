// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../interfaces/IDefense.sol";

/// @title PerAddressInvariantDefense — a behavioral (non-rate) defense.
/// @notice Enforces the invariant a buggy vault forgets: within a single
///         transaction, an address cannot withdraw more than its own recorded
///         balance. The per-caller cumulative is kept in TRANSIENT storage
///         (EIP-1153), so it accumulates across reentrant calls inside one tx
///         and auto-resets between txs.
///
///         This crosses the rate-limiting floor identified in the co-evolution
///         report: it stops fast AND patient reentrancy alike (any second
///         nested withdrawal exceeding the recorded balance is blocked),
///         regardless of drain rate, and never blocks a legitimate user
///         withdrawing within their balance — including a whale.
///
///         Expects ctx = abi.encode(recordedBalance, vaultBalance), as emitted
///         by the reentrancy scenario target.
contract PerAddressInvariantDefense is IDefense {
    function authorize(address caller, bytes4, uint256 value, bytes calldata ctx)
        external
        returns (bool)
    {
        (uint256 recordedBalance, ) = abi.decode(ctx, (uint256, uint256));
        bytes32 slot = keccak256(abi.encode("aegis.cumWithdrawn", caller));
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
