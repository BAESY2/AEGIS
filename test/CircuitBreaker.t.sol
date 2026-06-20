// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CircuitBreaker} from "../src/CircuitBreaker.sol";
import {MultiSourceConsensusGuard} from "../src/defenses/MultiSourceConsensusGuard.sol";

/// @notice A protocol that installs the breaker: a sensitive action is gated by
///         `whenLive`, the keeper trips it on detected manipulation, and only
///         governance can restart.
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
    address keeper = makeAddr("keeper");
    address gov = address(this);

    function setUp() public {
        address[] memory guardians = new address[](1);
        guardians[0] = keeper;
        breaker = new CircuitBreaker(guardians); // owner = this (governance)
        market = new ProtectedMarket(breaker);
    }

    function test_normal_operation_passes() public {
        market.borrow(100);
        assertEq(market.borrowed(), 100);
    }

    function test_keeper_trips_and_market_pauses() public {
        vm.prank(keeper);
        breaker.trip("oracle deviation 56x vs reference");
        assertTrue(breaker.tripped());
        vm.expectRevert(CircuitBreaker.Paused.selector);
        market.borrow(100);
    }

    function test_only_governance_resets() public {
        vm.prank(keeper);
        breaker.trip("manipulation");
        // a guardian cannot restart the market
        vm.prank(keeper);
        vm.expectRevert(CircuitBreaker.NotOwner.selector);
        breaker.reset();
        // governance can
        breaker.reset();
        assertFalse(breaker.tripped());
        market.borrow(50);
        assertEq(market.borrowed(), 50);
    }

    function test_random_address_cannot_trip() public {
        vm.prank(makeAddr("bad"));
        vm.expectRevert(CircuitBreaker.NotGuardian.selector);
        breaker.trip("griefing");
    }

    function test_onchain_auto_trip_from_defense_evidence() public {
        // wire a consensus guard as the on-chain auto-trip evidence
        breaker.setAutoTrip(new MultiSourceConsensusGuard(500)); // 5%
        // a manipulated price (one source 50x the others) => guard blocks => anyone can trip
        bytes memory manipulated = abi.encode(uint256(50000e18), uint256(1000e18), uint256(1000e18));
        vm.prank(makeAddr("anyone"));
        breaker.autoTripWith(manipulated);
        assertTrue(breaker.tripped());
        vm.expectRevert(CircuitBreaker.Paused.selector);
        market.borrow(1);
    }

    function test_auto_trip_reverts_on_genuine_price() public {
        breaker.setAutoTrip(new MultiSourceConsensusGuard(500));
        // three sources agree => guard allows => cannot trip
        bytes memory genuine = abi.encode(uint256(1000e18), uint256(1001e18), uint256(999e18));
        vm.expectRevert(bytes("defense allows: no manipulation"));
        breaker.autoTripWith(genuine);
        assertFalse(breaker.tripped());
    }
}
