// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../interfaces/IDefense.sol";

/// @title ReentrancyLockDefense — the classic non-reentrant lock, as a hook.
/// @notice A second *structural* defense for Scenario 01, recognizable to every
///         Solidity developer: a per-(caller, transaction) reentrancy lock. The
///         first authorize() for a caller in a transaction sets a transient flag
///         (EIP-1153) and allows the call; any subsequent authorize() for the
///         same caller in the same transaction — i.e. a reentrant nested
///         withdrawal — is blocked, and the flag auto-clears between transactions.
///
///         The lock is keyed by caller so that several *different* legitimate
///         users acting within one block are never confused for a single
///         reentrant actor. A reentrant attacker always re-enters as the same
///         caller, so it is caught at every drain rate.
///
///         Unlike a rate cap, it enforces an invariant ("at most one protected
///         entry per caller per transaction") rather than fitting a numeric
///         threshold, so it stops fast AND patient reentrancy alike and never
///         blocks a legitimate single withdrawal — including the whale's. It
///         therefore generalizes to unseen attackers, by a different mechanism
///         than the per-address balance invariant.
contract ReentrancyLockDefense is IDefense {
    function authorize(address caller, bytes4, uint256, bytes calldata) external returns (bool) {
        bytes32 slot = keccak256(abi.encode("aegis.reentrancy.lock", caller));
        uint256 entered;
        assembly {
            entered := tload(slot)
        }
        if (entered == 1) {
            return false; // this caller is already inside a protected call this tx
        }
        assembly {
            tstore(slot, 1)
        }
        return true;
    }
}
