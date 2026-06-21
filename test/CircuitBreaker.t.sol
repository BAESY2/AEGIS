// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CircuitBreaker, IPairLike} from "../src/CircuitBreaker.sol";

contract MockPair is IPairLike {
    uint112 r0;
    uint112 r1;

    constructor(uint112 _r0, uint112 _r1) {
        r0 = _r0;
        r1 = _r1;
    }

    function set(uint112 _r0, uint112 _r1) external {
        r0 = _r0;
        r1 = _r1;
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (r0, r1, 0);
    }
}

contract ProtectedMarket {
    CircuitBreaker public breaker;
    uint256 public borrowed;

    constructor(CircuitBreaker b) {
        breaker = b;
    }

    function borrow(uint256 amt) external {
        breaker.check(); // ---- the one-line firewall ----
        borrowed += amt;
    }
}

contract CircuitBreakerTest is Test {
    CircuitBreaker breaker;
    ProtectedMarket market;
    MockPair pa;
    MockPair pb;
    address keeper = makeAddr("keeper");

    function setUp() public {
        address[] memory g = new address[](1);
        g[0] = keeper;
        breaker = new CircuitBreaker(g, 100, 10); // 100-block bounded pause, 10-block cooldown
        market = new ProtectedMarket(breaker);
        pa = new MockPair(1000e6, 1e18); // ~$1000
        pb = new MockPair(1000e6, 1e18); // independent reference, agrees
        breaker.setSources(address(pa), address(pb), 500); // 5% auto-trip threshold
    }

    function test_normal_operation_passes() public {
        market.borrow(100);
        assertEq(market.borrowed(), 100);
    }

    function test_alert_only_by_default_does_not_pause() public {
        // default mode is ALERT_ONLY: a guardian "trip" only signals, never halts
        vm.prank(keeper);
        breaker.trip("suspicious divergence");
        assertFalse(breaker.isPaused());
        market.borrow(1); // still live
    }

    function test_griefing_blocked_when_sources_agree() public {
        breaker.setMode(CircuitBreaker.Mode.AUTO_PAUSE);
        // a random actor tries to grief a false pause; sources agree -> revert
        vm.prank(makeAddr("griefer"));
        vm.expectRevert(CircuitBreaker.NoManipulation.selector);
        breaker.autoTripFromSources();
        assertFalse(breaker.isPaused());
    }

    function test_auto_trip_only_on_real_divergence() public {
        breaker.setMode(CircuitBreaker.Mode.AUTO_PAUSE);
        // a REAL manipulation: source A's price moves 2x away from the reference
        pa.set(2000e6, 1e18);
        assertGt(breaker.currentDeviationBps(), 500);
        breaker.autoTripFromSources(); // now anyone may trip, because it's real
        assertTrue(breaker.isPaused());
        vm.expectRevert(CircuitBreaker.Paused_.selector);
        market.borrow(1);
    }

    function test_pause_is_bounded_and_self_heals() public {
        breaker.setMode(CircuitBreaker.Mode.AUTO_PAUSE);
        pa.set(2000e6, 1e18);
        breaker.autoTripFromSources();
        assertTrue(breaker.isPaused());
        // a false pause is NOT permanent: after maxPauseBlocks it auto-resumes
        vm.roll(block.number + 101);
        assertFalse(breaker.isPaused());
        market.borrow(7);
        assertEq(market.borrowed(), 7);
    }

    function test_governance_can_ratify_a_real_incident() public {
        breaker.setMode(CircuitBreaker.Mode.AUTO_PAUSE);
        pa.set(2000e6, 1e18);
        breaker.autoTripFromSources();
        breaker.ratify(); // governance confirms it's real -> hold past the timeout
        vm.roll(block.number + 101);
        assertTrue(breaker.isPaused()); // stays paused until reset
        breaker.reset();
        assertFalse(breaker.isPaused());
    }

    function test_cooldown_rate_limits_trips() public {
        breaker.setMode(CircuitBreaker.Mode.AUTO_PAUSE);
        pa.set(2000e6, 1e18);
        breaker.autoTripFromSources();
        breaker.reset();
        // within the cooldown window, cannot trip again
        vm.expectRevert(CircuitBreaker.Cooldown.selector);
        breaker.autoTripFromSources();
        vm.roll(block.number + 11);
        breaker.autoTripFromSources(); // ok after cooldown
        assertTrue(breaker.isPaused());
    }

    function test_only_governance_resets() public {
        breaker.setMode(CircuitBreaker.Mode.AUTO_PAUSE);
        pa.set(2000e6, 1e18);
        breaker.autoTripFromSources();
        vm.prank(keeper);
        vm.expectRevert(CircuitBreaker.NotOwner.selector);
        breaker.reset();
    }
}
