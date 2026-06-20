// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../interfaces/IDefense.sol";

/// @title BehavioralDefense — a feature-combining classifier (Scenario 05).
/// @notice Instead of one threshold, it combines two behavioral features —
///         transfer amount and whether the destination is new — into a rule:
///         block a withdrawal that is BOTH to a new destination AND at or above a
///         materiality floor. This is the shape a learned classifier finds: it
///         dominates the single-feature thresholds (higher recall at lower false
///         positives), because the owner's two ambiguous-but-legitimate habits
///         (a large payment to a *known* payee; a *small* payment to a new payee)
///         are each cleared by one of the two features.
///
///         Crucially it still cannot reach perfection: a patient thief who sends
///         a small amount to a new address is, by every observable, identical to
///         the owner paying a new payee. That residual overlap is the
///         irreducible frontier — the result this scenario is built to expose.
///
///         ctx = abi.encode(amount, isNewDestination).
contract BehavioralDefense is IDefense {
    uint256 public immutable materiality; // amount floor at which a new-payee transfer is suspicious

    constructor(uint256 _materiality) {
        materiality = _materiality;
    }

    function authorize(address, bytes4, uint256, bytes calldata ctx) external view returns (bool) {
        (uint256 amount, bool isNew) = abi.decode(ctx, (uint256, bool));
        if (isNew && amount >= materiality) {
            return false; // material transfer to a never-seen destination
        }
        return true;
    }
}
