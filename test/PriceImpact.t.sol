// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PriceImpactGuard} from "../src/defenses/PriceImpactGuard.sol";

/// @notice Pure (no-fork) coverage of the price-impact math and the allow/block
///         frontier on synthetic constant-product reserves.
contract PriceImpactTest is Test {
    PriceImpactGuard guard;

    function setUp() public {
        guard = new PriceImpactGuard(200); // 2% cap
    }

    function test_zero_inputs_are_safe() public view {
        assertEq(guard.impactBps(0, 1000, 10), 0);
        assertEq(guard.impactBps(1000, 0, 10), 0);
        assertEq(guard.impactBps(1000, 1000, 0), 0);
    }

    function test_small_trade_low_impact() public view {
        // 0.1% of a balanced pool -> ~20 bps, allowed under the 2% cap
        uint256 imp = guard.impactBps(1_000_000 ether, 1_000_000 ether, 1_000 ether);
        assertLt(imp, 200);
        assertTrue(guard.authorize(address(0), bytes4(0), 0, abi.encode(uint256(1_000_000 ether), uint256(1_000_000 ether), uint256(1_000 ether))));
    }

    function test_large_trade_blocked() public view {
        // 50% of the pool -> >50% price move, blocked
        uint256 imp = guard.impactBps(1_000_000 ether, 1_000_000 ether, 500_000 ether);
        assertGt(imp, 5000);
        assertFalse(guard.authorize(address(0), bytes4(0), 0, abi.encode(uint256(1_000_000 ether), uint256(1_000_000 ether), uint256(500_000 ether))));
    }

    function test_impact_is_monotonic_in_size() public view {
        uint256 r = 1_000_000 ether;
        uint256 a = guard.impactBps(r, r, 1_000 ether);
        uint256 b = guard.impactBps(r, r, 10_000 ether);
        uint256 c = guard.impactBps(r, r, 100_000 ether);
        assertLt(a, b);
        assertLt(b, c);
    }
}
