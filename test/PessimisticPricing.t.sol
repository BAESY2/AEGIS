// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PessimisticLPGuard} from "../src/defenses/PessimisticLPGuard.sol";
import {PessimisticPriceGuard} from "../src/defenses/PessimisticPriceGuard.sol";

/// @notice The two production-proven pessimistic-pricing defenses (Inverse FiRM):
///         min-of-underlyings LP valuation, and a trailing-low borrow-power floor.
contract PessimisticPricingTest is Test {
    // ---- PessimisticLPGuard ----
    function test_lp_blocks_overvaluation_from_pool_skew() public {
        PessimisticLPGuard g = new PessimisticLPGuard(50); // 0.5% tolerance
        // underlyings ~$1 each, virtual price 1.02 -> fair LP ~= 1.02
        uint256 pa = 1e18;
        uint256 pb = 1e18;
        uint256 vp = 1.02e18;
        // honest valuation at the fair price passes
        assertTrue(g.authorize(address(0), bytes4(0), 0, abi.encode(uint256(1.02e18), pa, pb, vp)));
        // an attacker claims the LP is worth far more (skewed toward the "rich" side)
        assertFalse(g.authorize(address(0), bytes4(0), 0, abi.encode(uint256(1.5e18), pa, pb, vp)));
        // depeg of one underlying: min() drops the fair value, blocking stale-high claims
        assertFalse(g.authorize(address(0), bytes4(0), 0, abi.encode(uint256(1.02e18), pa, uint256(0.7e18), vp)));
    }

    // ---- PessimisticPriceGuard ----
    function test_floor_blocks_spike_and_tracks_low() public {
        // window 100 blocks, 1% tolerance, initial price $1000
        PessimisticPriceGuard g = new PessimisticPriceGuard(100, 100, 1000e18);

        // a price near the floor is allowed
        vm.roll(block.number + 10);
        assertTrue(g.authorize(address(0), bytes4(0), 0, abi.encode(uint256(1005e18))));

        // a manipulated 3x spike is far above the trailing low -> blocked
        vm.roll(block.number + 1);
        assertFalse(g.authorize(address(0), bytes4(0), 0, abi.encode(uint256(3000e18))));
        // and the spike did not raise the floor
        assertEq(g.floor(), 1000e18);
    }

    function test_genuine_low_lowers_the_floor() public {
        PessimisticPriceGuard g = new PessimisticPriceGuard(100, 100, 1000e18);
        vm.roll(block.number + 5);
        // a real drop to $900 is accepted and becomes the new floor
        assertTrue(g.authorize(address(0), bytes4(0), 0, abi.encode(uint256(900e18))));
        assertEq(g.floor(), 900e18);
        // now even $950 is above floor*1.01 -> conservatively blocked until it persists
        assertFalse(g.authorize(address(0), bytes4(0), 0, abi.encode(uint256(950e18))));
    }

    function test_persisted_rise_eventually_allowed() public {
        PessimisticPriceGuard g = new PessimisticPriceGuard(100, 100, 1000e18);
        // hold ~1000 across two full windows so the floor rolls up to ~1000
        vm.roll(block.number + 101);
        g.authorize(address(0), bytes4(0), 0, abi.encode(uint256(1000e18)));
        vm.roll(block.number + 101);
        g.authorize(address(0), bytes4(0), 0, abi.encode(uint256(1000e18)));
        // a price within tolerance of the persisted floor passes
        vm.roll(block.number + 1);
        assertTrue(g.authorize(address(0), bytes4(0), 0, abi.encode(uint256(1008e18))));
    }
}
