// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../interfaces/IDefense.sol";

/// @title RateLimitDefense — a circuit-breaker reference defense (ERC-7265 spirit).
/// @notice Tracks cumulative outflow per block. A reentrancy drain executes many
///         withdrawals inside a single transaction (one block), so cumulative
///         outflow blows past the cap and the breaker trips. Normal users making
///         single, reasonable withdrawals across different blocks pass cleanly.
///
///         This is a baseline, not the ceiling: its weakness is that a legit
///         large withdrawal can also trip it. Tightening that precision/recall
///         tradeoff is exactly what a learned defense is meant to improve.
contract RateLimitDefense is IDefense {
    uint256 public immutable maxOutflowPerBlock;
    uint256 public lastBlock;
    uint256 public windowOutflow;

    constructor(uint256 _maxOutflowPerBlock) {
        maxOutflowPerBlock = _maxOutflowPerBlock;
    }

    function authorize(
        address, /* caller */
        bytes4, /* selector */
        uint256 value,
        bytes calldata /* ctx */
    ) external returns (bool) {
        if (block.number != lastBlock) {
            lastBlock = block.number;
            windowOutflow = 0;
        }
        windowOutflow += value;
        return windowOutflow <= maxOutflowPerBlock;
    }
}
