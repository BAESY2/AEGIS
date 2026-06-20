// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../interfaces/IDefense.sol";

/// @title AmountThresholdDefense — a single-feature anomaly filter (Scenario 05).
/// @notice Blocks a withdrawal whose amount exceeds a cap. It is one point on the
///         precision/recall frontier: a low cap catches the greedy thief but
///         false-positives the owner's legitimate large withdrawals; a high cap
///         spares the owner but lets the thief through. Using amount alone, it
///         cannot do better than its ROC point.
contract AmountThresholdDefense is IDefense {
    uint256 public immutable cap;

    constructor(uint256 _cap) {
        cap = _cap;
    }

    function authorize(address, bytes4, uint256 value, bytes calldata) external view returns (bool) {
        return value <= cap; // value == amount
    }
}
