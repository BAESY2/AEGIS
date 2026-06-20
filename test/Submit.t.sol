// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VulnerableVault} from "../src/scenarios/reentrancy/VulnerableVault.sol";
import {PatientReentrancyAttacker} from "../src/scenarios/reentrancy/PatientReentrancyAttacker.sol";
import {IDefense} from "../src/interfaces/IDefense.sol";
import {Submission} from "../submissions/Submission.sol";

/// @notice Scores a user-submitted defense (submissions/Submission.sol) on the
///         reentrancy scenario — no registry edits required. The `aegis submit`
///         driver calls this across the attacker grid and reports the worst-case
///         reward and the rank. This is the local form of the hosted submission
///         flow that, when run for many contributors, produces the multi-party
///         dataset the project's moat rests on.
contract Submit is Test {
    uint256 constant TVL = 10 ether;
    uint256 constant CHUNK = 1 ether;
    uint256 constant WHALE = 4 ether;
    uint256 constant BENIGN_TOTAL = 4;
    uint256 constant SPACING = 16;

    function _savedFraction(uint256 take, uint256 horizon) internal returns (uint256) {
        VulnerableVault vault = new VulnerableVault(new Submission());
        address victim = makeAddr("victim");
        vm.deal(victim, TVL);
        vm.prank(victim);
        vault.deposit{value: TVL}();

        PatientReentrancyAttacker attacker = new PatientReentrancyAttacker(vault, take);
        vm.deal(address(this), CHUNK);
        attacker.seed{value: CHUNK}();
        for (uint256 b = 0; b < horizon; b++) {
            try attacker.pulse() {} catch {}
            vm.roll(block.number + 1);
        }
        uint256 extracted = address(attacker).balance;
        uint256 loss = extracted > CHUNK ? extracted - CHUNK : 0;
        if (loss >= TVL) return 0;
        return ((TVL - loss) * 1e18) / TVL;
    }

    function _falsePositives() internal returns (uint256 fp) {
        VulnerableVault vault = new VulnerableVault(new Submission());
        for (uint256 i = 0; i < 3; i++) {
            address u = makeAddr(string(abi.encodePacked("retail", i)));
            vm.deal(u, CHUNK);
            vm.prank(u);
            vault.deposit{value: CHUNK}();
            vm.roll(block.number + SPACING);
            vm.prank(u);
            try vault.withdraw(CHUNK) {} catch {
                fp++;
            }
        }
        address whale = makeAddr("whale");
        vm.deal(whale, WHALE);
        vm.prank(whale);
        vault.deposit{value: WHALE}();
        vm.roll(block.number + SPACING);
        vm.prank(whale);
        try vault.withdraw(WHALE) {} catch {
            fp++;
        }
    }

    function test_submit() public {
        uint256 take = vm.envOr("AEGIS_TAKE", uint256(11)) * 1 ether;
        uint256 horizon = vm.envOr("AEGIS_HORIZON", uint256(12));
        uint256 saved = _savedFraction(take, horizon);
        uint256 fp = _falsePositives();
        int256 reward = int256(saved) - int256((fp * 1e18) / BENIGN_TOTAL);
        vm.writeFile(
            "./scoring/submission.json",
            string(abi.encodePacked(
                '{"take_eth":', vm.toString(take / 1 ether),
                ',"saved_frac_1e18":', vm.toString(saved),
                ',"fp":', vm.toString(fp),
                ',"reward_1e18":', vm.toString(reward), "}"
            ))
        );
    }
}
