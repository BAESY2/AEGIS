// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../interfaces/IDefense.sol";

/// @title PessimisticLPGuard — value an AMM LP token at min(underlyings) × virtual price.
/// @notice The Curve-LP collateral defense Inverse FiRM hand-built. A protocol that
///         prices LP-token collateral by its *fair* composition can be gamed: an
///         attacker skews the pool (swaps it heavily toward the cheaper asset) so the
///         LP appears to hold more of the "valuable" side, inflating the price and the
///         borrow power. The fix, proven in production: price the LP at
///         `min(price of each underlying) × virtual_price`. Pool skew can then only
///         move the valuation DOWN (toward the cheaper asset), never up — so it can
///         never inflate collateral.
///
///         ctx = abi.encode(claimedLpPrice, priceUnderlyingA, priceUnderlyingB, virtualPrice),
///         all 1e18-scaled. The guard allows the action only if the protocol's
///         claimed LP price does not exceed the pessimistic value (within `tolBps`).
contract PessimisticLPGuard is IDefense {
    uint256 public immutable tolBps;

    constructor(uint256 _tolBps) {
        tolBps = _tolBps;
    }

    function authorize(address, bytes4, uint256, bytes calldata ctx) external view returns (bool) {
        (uint256 claimed, uint256 pa, uint256 pb, uint256 virtualPrice) =
            abi.decode(ctx, (uint256, uint256, uint256, uint256));
        uint256 lo = pa < pb ? pa : pb;
        uint256 fair = (lo * virtualPrice) / 1e18; // min underlying × virtual price
        uint256 ceil = fair + (fair * tolBps) / 10000;
        return claimed <= ceil;
    }
}
