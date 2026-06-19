// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../interfaces/IDefense.sol";

/// @title LaggedOracleGuard — the frontier-crossing defense for scenario 02.
/// @notice Compares spot to the AMM's ONE-BLOCK-LAGGED price (a mini-TWAP) rather
///         than a fixed anchor. A single-block manipulation cannot move the
///         lagged price, so any same-block pump — regardless of size — shows a
///         large spot/lagged divergence and is blocked, while genuine multi-block
///         drift is reflected in the lagged price and passes. This crosses the
///         floor that the fixed-anchor guard hits (where a small pump is
///         indistinguishable from organic drift).
contract LaggedOracleGuard is IDefense {
    uint256 public immutable maxDeviationBps;

    constructor(uint256 _maxDeviationBps) {
        maxDeviationBps = _maxDeviationBps;
    }

    function authorize(address, bytes4, uint256, bytes calldata ctx) external view returns (bool) {
        (uint256 spot, uint256 lagged) = abi.decode(ctx, (uint256, uint256));
        if (lagged == 0) return true;
        uint256 diff = spot > lagged ? spot - lagged : lagged - spot;
        return (diff * 10000) / lagged <= maxDeviationBps;
    }
}
