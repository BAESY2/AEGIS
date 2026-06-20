// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProtectedSwapPool} from "../examples/ProtectedSwapPool.sol";
import {PriceImpactGuard} from "../src/defenses/PriceImpactGuard.sol";
import {CumulativeImpactGuard} from "../src/defenses/CumulativeImpactGuard.sol";
import {IDefense} from "../src/interfaces/IDefense.sol";

/// @notice The split-trade attack and its fix, end-to-end on a real swap path.
///         A single-trade price-impact cap is EVADED by chopping a drain into many
///         sub-cap trades — the pool still empties. The stateful, windowed
///         CumulativeImpactGuard (a drop-in with the same ctx) blocks the same
///         attack once the cumulative footprint crosses the window cap, while a
///         legitimate trader who spreads volume across windows is unaffected.
contract SplitTradeEvasion is Test {
    uint256 constant R0 = 2_000_000_000e6; // 2B USDC (out)
    uint256 constant R1 = 1_000_000 ether; // 1M WETH (in)

    address constant ATTACKER = address(0xA11ACE);
    address constant TRADER = address(0xB0B);

    function _pool(IDefense d) internal returns (ProtectedSwapPool) {
        return new ProtectedSwapPool(R0, R1, d);
    }

    /// Negative result: a per-trade 2% cap lets a split drain through.
    function test_per_trade_cap_is_evaded_by_splitting() public {
        ProtectedSwapPool pool = _pool(new PriceImpactGuard(200)); // 2% per-trade
        uint256 chunk = R1 / 100; // 1% of the pool per trade -> under the 2% cap
        uint256 executed = 0;
        vm.startPrank(ATTACKER);
        for (uint256 i = 0; i < 30; i++) {
            pool.swap(chunk, 0);
            executed++;
        }
        vm.stopPrank();
        assertEq(executed, 30, "every sub-cap trade was allowed");
        // the pool was meaningfully drained despite the per-trade cap
        uint256 drainedBps = ((R0 - pool.reserve0()) * 10000) / R0;
        emit log_named_uint("USDC drained (bps of pool)", drainedBps);
        assertGt(drainedBps, 1500, "split trades drained >15% of the pool");
    }

    /// Fix: a windowed cumulative-footprint cap blocks the same split attack.
    function test_windowed_cumulative_cap_blocks_the_split() public {
        // 5% cumulative footprint allowed per 5-minute window
        ProtectedSwapPool pool = _pool(new CumulativeImpactGuard(300, 500));
        uint256 chunk = R1 / 100; // 1% each
        uint256 executed = 0;
        vm.startPrank(ATTACKER);
        for (uint256 i = 0; i < 30; i++) {
            try pool.swap(chunk, 0) {
                executed++;
            } catch {
                break;
            }
        }
        vm.stopPrank();
        // ~5 chunks of 1% fit under the 5% window cap; the 6th is blocked
        assertLe(executed, 5, "cumulative cap halts the drain early");
        uint256 drainedBps = ((R0 - pool.reserve0()) * 10000) / R0;
        emit log_named_uint("executed sub-trades", executed);
        emit log_named_uint("USDC drained (bps of pool)", drainedBps);
        assertLt(drainedBps, 600, "drain held under ~6% of the pool");
    }

    /// A legitimate trader spreading volume across windows is unaffected.
    function test_legitimate_trader_across_windows_is_allowed() public {
        ProtectedSwapPool pool = _pool(new CumulativeImpactGuard(300, 500));
        uint256 chunk = R1 / 100; // 1%
        vm.startPrank(TRADER);
        // 4% in this window: allowed
        for (uint256 i = 0; i < 4; i++) {
            pool.swap(chunk, 0);
        }
        // next window: the cumulative counter resets
        vm.warp(block.timestamp + 301);
        for (uint256 i = 0; i < 4; i++) {
            pool.swap(chunk, 0);
        }
        vm.stopPrank();
        assertTrue(true, "spread-out legitimate volume passes across windows");
    }
}
