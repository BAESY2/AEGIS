// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../interfaces/IDefense.sol";

/// @title MultiSourceConsensusGuard — require multiple price sources to agree.
/// @notice ctx = abi.encode(priceA, priceB, priceC), all same-scaled. The guard
///         allows the action only if the three sources are mutually consistent —
///         their spread is within `maxDeviationBps` of the median. An attacker
///         who manipulates ONE venue (e.g. a single AMM) within a transaction
///         cannot move the others (an independent AMM and a Chainlink feed) in
///         the same block, so the manipulated source becomes an outlier, the
///         spread blows up, and the action is blocked — while a genuine price
///         (all venues agreeing) passes. Demonstrated on real mainnet state in
///         test/ForkConsensus.t.sol against live Uniswap V2, Sushiswap, and the
///         Chainlink ETH/USD feed.
contract MultiSourceConsensusGuard is IDefense {
    uint256 public immutable maxDeviationBps;

    constructor(uint256 _maxDeviationBps) {
        maxDeviationBps = _maxDeviationBps;
    }

    function _median(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        if ((a >= b && a <= c) || (a <= b && a >= c)) return a;
        if ((b >= a && b <= c) || (b <= a && b >= c)) return b;
        return c;
    }

    function authorize(address, bytes4, uint256, bytes calldata ctx) external view returns (bool) {
        (uint256 a, uint256 b, uint256 c) = abi.decode(ctx, (uint256, uint256, uint256));
        uint256 hi = a > b ? (a > c ? a : c) : (b > c ? b : c);
        uint256 lo = a < b ? (a < c ? a : c) : (b < c ? b : c);
        uint256 med = _median(a, b, c);
        if (med == 0) return true;
        return ((hi - lo) * 10000) / med <= maxDeviationBps;
    }
}
