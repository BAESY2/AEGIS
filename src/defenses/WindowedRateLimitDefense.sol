// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../interfaces/IDefense.sol";

/// @title WindowedRateLimitDefense — a tumbling-window circuit breaker.
/// @notice Caps cumulative outflow over a window of `windowBlocks` blocks.
///         windowBlocks == 1 reduces to a per-block limiter (the defense a
///         fast, single-tx reentrancy drain trips). Larger windows accumulate
///         across blocks, which is what catches a PATIENT attacker that drains
///         slowly to stay under any per-block cap — at the cost of summing more
///         legitimate traffic, so the window cannot be made arbitrarily wide.
contract WindowedRateLimitDefense is IDefense {
    uint256 public immutable windowBlocks;
    uint256 public immutable capPerWindow;
    uint256 public windowStart;
    uint256 public windowOutflow;

    constructor(uint256 _windowBlocks, uint256 _capPerWindow) {
        windowBlocks = _windowBlocks == 0 ? 1 : _windowBlocks;
        capPerWindow = _capPerWindow;
    }

    function authorize(address, bytes4, uint256 value, bytes calldata) external returns (bool) {
        if (block.number >= windowStart + windowBlocks) {
            windowStart = block.number;
            windowOutflow = 0;
        }
        windowOutflow += value;
        return windowOutflow <= capPerWindow;
    }
}
