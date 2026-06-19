// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../src/interfaces/IDefense.sol";

/// @title TemplateDefense — copy this to src/defenses/ to start a new defense.
/// @notice A defense implements exactly one method. The protocol calls it at the
///         top of a sensitive action; return `true` to ALLOW, `false` to BLOCK
///         (the protocol then reverts the action).
///
///         Scoring rewards PRECISION, not paranoia: blocking everything earns
///         the funds-saved term but pays the full false-positive penalty, netting
///         zero. To win, stop the exploit while letting legitimate users through.
///
///         Tips:
///           * `value` is the economic magnitude (e.g. withdrawal amount, wei).
///           * `ctx` is scenario-specific — DECODE the exact tuple the target
///             documents (e.g. reentrancy passes abi.encode(recordedBalance,
///             vaultBalance); access passes abi.encode(admin)).
///           * State is allowed. For per-transaction accumulators that must reset
///             between txs, use EIP-1153 transient storage (tstore/tload) — see
///             src/defenses/PerAddressInvariantDefense.sol.
///           * The strongest defenses enforce an INVARIANT (structural) rather
///             than fit a numeric threshold; those generalize to unseen attackers.
contract TemplateDefense is IDefense {
    function authorize(
        address caller,
        bytes4 selector,
        uint256 value,
        bytes calldata ctx
    ) external returns (bool allow) {
        // EXAMPLE: a no-op that allows everything (reward ~0). Replace with your
        // own invariant or signal. Silence unused-variable warnings:
        caller;
        selector;
        value;
        ctx;
        return true;
    }
}
