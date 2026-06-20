// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../interfaces/IDefense.sol";

/// @title CumulativeImpactGuard — stateful, windowed footprint cap per caller.
/// @notice A single-trade impact cap (see PriceImpactGuard) is evaded by SPLITTING
///         a drain into many trades that each stay under the per-trade limit. This
///         guard closes that hole: it accumulates a caller's traded notional
///         relative to the pool's liquidity over a rolling time window and blocks
///         once the cumulative footprint exceeds `maxWindowBps`. It is a drop-in
///         replacement for PriceImpactGuard — same ctx contract
///         `(reserveIn, reserveOut, amountIn)` — so a protocol upgrades its
///         defense without touching its swap path.
///
///         State is keyed by the `caller` the protocol passes (trusted msg.sender
///         of the protected call). The window anchors its liquidity reference to
///         the reserve observed when the window opened, so the cap measures
///         cumulative drain against the liquidity the attacker started from.
///
///         This is the liquidity-family analogue of the project's central result:
///         a stateless per-event boundary overfits to single trades; a stateful
///         invariant over a window holds against the split-trade attack that
///         defeats it. Demonstrated in test/SplitTradeEvasion.t.sol.
contract CumulativeImpactGuard is IDefense {
    uint256 public immutable windowSeconds;
    uint256 public immutable maxWindowBps;

    struct Window {
        uint64 start;
        uint256 cumAmount;
        uint256 refReserve;
    }

    mapping(address => Window) public windows;

    constructor(uint256 _windowSeconds, uint256 _maxWindowBps) {
        windowSeconds = _windowSeconds;
        maxWindowBps = _maxWindowBps;
    }

    function authorize(address caller, bytes4, uint256, bytes calldata ctx) external returns (bool) {
        (uint256 reserveIn, , uint256 amountIn) = abi.decode(ctx, (uint256, uint256, uint256));
        Window storage w = windows[caller];

        // open a fresh window if the previous one has elapsed (or never existed)
        if (w.refReserve == 0 || block.timestamp - w.start > windowSeconds) {
            w.start = uint64(block.timestamp);
            w.cumAmount = 0;
            w.refReserve = reserveIn;
        }

        w.cumAmount += amountIn;
        if (w.refReserve == 0) return true; // degenerate empty pool
        return (w.cumAmount * 10000) / w.refReserve <= maxWindowBps;
    }
}
