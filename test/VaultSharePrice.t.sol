// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VaultSharePriceGuard} from "../src/defenses/VaultSharePriceGuard.sol";

/// @notice The donation/share-price-inflation class (Resupply $9.6M, Jun 2025):
///         normal yield accrues gradually and passes; a single-block donation
///         spike to the share price is blocked, and a rejected spike never
///         poisons the guard's baseline.
contract VaultSharePriceTest is Test {
    VaultSharePriceGuard guard;
    uint256 constant PPS0 = 1e18; // 1.0 share price

    function setUp() public {
        // allow up to 1 bp of share-price growth per block (gradual real yield)
        guard = new VaultSharePriceGuard(1, PPS0);
    }

    function _auth(uint256 pps) internal returns (bool) {
        return guard.authorize(address(0), bytes4(0), 0, abi.encode(pps));
    }

    function test_gradual_yield_passes() public {
        vm.roll(block.number + 100);
        // +0.5% over 100 blocks = within the 1bp/block budget
        assertTrue(_auth((PPS0 * 10050) / 10000));
        vm.roll(block.number + 200);
        assertTrue(_auth((PPS0 * 10120) / 10000));
    }

    function test_donation_spike_is_blocked() public {
        vm.roll(block.number + 1);
        // attacker donates underlying -> share price doubles in one block
        assertFalse(_auth(PPS0 * 2));
        // baseline was not poisoned: the next genuine, gradual reading still passes
        vm.roll(block.number + 50);
        assertTrue(_auth((PPS0 * 10030) / 10000));
    }

    function test_falling_price_always_passes() public {
        vm.roll(block.number + 1);
        assertTrue(_auth((PPS0 * 9000) / 10000)); // a loss is not an inflation attack
    }

    function test_small_spike_within_budget_passes() public {
        vm.roll(block.number + 500);
        // 500 blocks * 1bp = 5% budget; a 4% rise passes
        assertTrue(_auth((PPS0 * 10400) / 10000));
    }
}
