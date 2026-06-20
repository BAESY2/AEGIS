// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../interfaces/IDefense.sol";

/// @title PriceImpactGuard — cap how far a single swap may move a constant-product pool.
/// @notice A liquidity-aware guard. It does not ask "is the price true?" (that is
///         the oracle family) — it asks "does THIS trade move the pool too far in
///         one shot?". `ctx = abi.encode(reserveIn, reserveOut, amountIn)` for the
///         pool being traded against. It computes the post-trade mid-price move of
///         a Uniswap-V2-style constant-product swap (0.30% fee) and blocks when
///         that move exceeds `maxImpactBps`.
///
///         This is the signal behind flash drains and the setup leg of a sandwich:
///         a single transaction that consumes a large fraction of the pool swings
///         the price violently. A normal-sized trade barely moves it. Capping
///         per-trade impact relative to LIVE liquidity is distinct from rate
///         limits (absolute value over time) and from oracle guards (price truth):
///         it bounds the action's own market footprint. Validated on the live
///         Uniswap V2 USDC/WETH pool in test/ForkImpact.t.sol.
contract PriceImpactGuard is IDefense {
    uint256 public immutable maxImpactBps;

    constructor(uint256 _maxImpactBps) {
        maxImpactBps = _maxImpactBps;
    }

    /// @dev Mid-price (reserveOut/reserveIn) move caused by swapping `amountIn`,
    ///      in basis points. For constant product with a 0.30% fee the input
    ///      reserve grows by the full amountIn while the output reserve shrinks by
    ///      amountOut; the mid-price move equals
    ///          1 - (reserveOut'/reserveIn') / (reserveOut/reserveIn).
    ///      Returned in bps (10000 = 100%).
    function impactBps(uint256 reserveIn, uint256 reserveOut, uint256 amountIn)
        public
        pure
        returns (uint256)
    {
        if (reserveIn == 0 || reserveOut == 0 || amountIn == 0) return 0;
        uint256 amountInWithFee = amountIn * 997;
        uint256 amountOut = (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
        uint256 newReserveIn = reserveIn + amountIn;
        uint256 newReserveOut = reserveOut - amountOut;
        // priceAfter/priceBefore = (newReserveOut/newReserveIn) / (reserveOut/reserveIn)
        //                        = (newReserveOut * reserveIn) / (reserveOut * newReserveIn)
        uint256 ratioBps = (newReserveOut * reserveIn * 10000) / (reserveOut * newReserveIn);
        if (ratioBps >= 10000) return 0; // price did not fall (rounding/degenerate)
        return 10000 - ratioBps;
    }

    function authorize(address, bytes4, uint256, bytes calldata ctx) external view returns (bool) {
        (uint256 reserveIn, uint256 reserveOut, uint256 amountIn) =
            abi.decode(ctx, (uint256, uint256, uint256));
        return impactBps(reserveIn, reserveOut, amountIn) <= maxImpactBps;
    }
}
