// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IDefense} from "../../src/interfaces/IDefense.sol";
import {Reward} from "../../src/lib/Reward.sol";
import {VulnerableVault} from "../../src/scenarios/reentrancy/VulnerableVault.sol";
import {ReentrancyAttacker} from "../../src/scenarios/reentrancy/ReentrancyAttacker.sol";
import {RateLimitDefense} from "../../src/defenses/RateLimitDefense.sol";

/// @notice Shared measurement core for Scenario 01. The benign suite now
///         includes a legitimate WHALE making one large withdrawal, which
///         creates real precision/recall tension: a cap set too low blocks the
///         whale (false positive), a cap set too high lets the drain through.
///         There is no longer a hand-coded "right answer" — it must be found.
abstract contract ReentrancyScenario is Test {
    uint256 internal constant TVL = 10 ether; // honest funds the attacker targets
    uint256 internal constant CHUNK = 1 ether; // attacker seed / drain step (drains ~11)
    uint256 internal constant WHALE = 5 ether; // one legitimate large withdrawal
    uint256 internal constant BENIGN_TOTAL = 4; // 3 small users + 1 whale

    function _measureAttack(IDefense def) internal returns (bool blocked) {
        VulnerableVault vault = new VulnerableVault(def);
        address victim = makeAddr("victim");
        vm.deal(victim, TVL);
        vm.prank(victim);
        vault.deposit{value: TVL}();

        ReentrancyAttacker attacker = new ReentrancyAttacker(vault);
        vm.deal(address(this), CHUNK);
        try attacker.attack{value: CHUNK}() {} catch {}
        blocked = vault.totalAssets() >= TVL;
    }

    function _measureFalsePositives(IDefense def) internal returns (uint256 fp) {
        VulnerableVault vault = new VulnerableVault(def);

        // three honest "retail" users, each a single small withdrawal
        for (uint256 i = 0; i < 3; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));
            vm.deal(user, CHUNK);
            vm.prank(user);
            vault.deposit{value: CHUNK}();
            vm.roll(block.number + 1);
            vm.prank(user);
            try vault.withdraw(CHUNK) {} catch {
                fp++;
            }
        }

        // one honest whale: a single, large, perfectly legitimate withdrawal
        address whale = makeAddr("whale");
        vm.deal(whale, WHALE);
        vm.prank(whale);
        vault.deposit{value: WHALE}();
        vm.roll(block.number + 1);
        vm.prank(whale);
        try vault.withdraw(WHALE) {} catch {
            fp++;
        }
    }

    /// Evaluate a RateLimit defense configured with `capWei` and return the
    /// execution-derived reward plus its components.
    function _evaluateCap(uint256 capWei)
        internal
        returns (int256 reward, bool blocked, uint256 fp)
    {
        blocked = _measureAttack(new RateLimitDefense(capWei));
        fp = _measureFalsePositives(new RateLimitDefense(capWei));
        reward = Reward.score(blocked, fp, BENIGN_TOTAL);
    }
}
