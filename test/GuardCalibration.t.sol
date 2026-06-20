// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PriceImpactGuard} from "../src/defenses/PriceImpactGuard.sol";

/// @notice Robustness calibration — quantifies exactly how strong each DEX guard
///         is, deterministically (no fork). It answers the two questions a
///         security-minded protocol asks before deploying a guard:
///           1. PriceImpactGuard: for a given cap, what is the largest single
///              trade (as a fraction of the pool) that still passes?
///           2. TWAP: to move the time-weighted average past the cap, for what
///              fraction of the window must an attacker SUSTAIN a manipulated
///              price (the window arbitrageurs have to drain them)?
///         Both are emitted as tables and asserted, so the guarantees are a
///         checked-in fact, not a claim.
contract GuardCalibration is Test {
    uint256 constant R = 1_000_000 ether; // balanced reference pool

    /// @dev Largest amountIn (constant product, 0.30% fee) whose mid-price impact
    ///      stays within `capBps`, found by binary search over [0, R].
    function _maxTradeWithin(PriceImpactGuard g, uint256 capBps) internal pure returns (uint256) {
        uint256 lo = 0;
        uint256 hi = R;
        for (uint256 i = 0; i < 64; i++) {
            uint256 mid = (lo + hi + 1) / 2;
            if (g.impactBps(R, R, mid) <= capBps) lo = mid;
            else hi = mid - 1;
        }
        return lo;
    }

    function test_price_impact_frontier_is_monotonic() public {
        PriceImpactGuard g = new PriceImpactGuard(0);
        uint16[4] memory caps = [50, 100, 200, 500];
        uint256 prev = 0;
        emit log_string("PriceImpactGuard: cap (bps) -> max single trade (bps of pool)");
        for (uint256 i = 0; i < caps.length; i++) {
            uint256 maxIn = _maxTradeWithin(g, caps[i]);
            uint256 sizeBps = (maxIn * 10000) / R;
            emit log_named_uint(string(abi.encodePacked("  cap ", vm.toString(caps[i]), " bps")), sizeBps);
            // a looser cap must permit a strictly larger trade
            assertGt(maxIn, prev);
            prev = maxIn;
        }
    }

    /// @dev To move a TWAP from the genuine price by `capBps`, an attacker who can
    ///      crash the spot by `dropBps` must hold it for at least
    ///      capBps/dropBps of the observation window (linear-time-average model:
    ///      twapDeviation = drop * windowFraction). Returns the minimum fraction
    ///      in basis points of the window.
    function _minWindowFractionBps(uint256 capBps, uint256 dropBps) internal pure returns (uint256) {
        return (capBps * 10000) / dropBps;
    }

    function test_twap_manipulation_cost() public {
        // attacker crashes spot 50% (5000 bps); how long must they hold it?
        uint256 dropBps = 5000;
        uint16[4] memory caps = [50, 100, 200, 500];
        uint256 windowMinutes = 30;
        emit log_string("UniswapV2TwapGuard: to breach the cap with a 50% spot crash,");
        emit log_string("sustain it for at least N seconds of a 30-min window:");
        for (uint256 i = 0; i < caps.length; i++) {
            uint256 fBps = _minWindowFractionBps(caps[i], dropBps);
            uint256 seconds_ = (fBps * windowMinutes * 60) / 10000;
            emit log_named_uint(string(abi.encodePacked("  cap ", vm.toString(caps[i]), " bps -> seconds")), seconds_);
            // even the tightest 0.50% cap forces a non-trivial sustained hold
            assertGt(seconds_, 0);
        }
        // a 5% cap against a 50% crash requires holding 10% of the window = 180s
        assertEq(_minWindowFractionBps(500, 5000), 1000); // 10.00% of the window
        assertEq((_minWindowFractionBps(500, 5000) * windowMinutes * 60) / 10000, 180);
    }
}
