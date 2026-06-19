// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console2} from "forge-std/Test.sol";
import {ReentrancyScenario} from "./base/ReentrancyScenario.sol";
import {IDefense} from "../src/interfaces/IDefense.sol";
import {Reward} from "../src/lib/Reward.sol";
import {RateLimitDefense} from "../src/defenses/RateLimitDefense.sol";
import {ParanoidDefense} from "../src/defenses/ParanoidDefense.sol";

/// @notice Static scoreboard for Scenario 01 against the harder benign suite
///         (now including a legitimate whale). Note the hand-picked RateLimit
///         cap of 2 ether is *suboptimal* — it false-positives the whale and
///         scores 0.75. Finding the cap that reaches 1.0 is the gym's job.
contract ReentrancyScoreboard is ReentrancyScenario {
    function _show(string memory name, IDefense aDef, IDefense fDef)
        internal
        returns (int256 reward)
    {
        bool blocked = _measureAttack(aDef);
        uint256 fp = _measureFalsePositives(fDef);
        reward = Reward.score(blocked, fp, BENIGN_TOTAL);
        console2.log("=== defense:", name, "===");
        console2.log("  attack blocked :", blocked);
        console2.log("  false positives:", fp, "/", BENIGN_TOTAL);
        console2.log("  reward (1e18)  :");
        console2.logInt(reward);
    }

    function test_scoreboard() public {
        int256 rNone = _show("NoDefense", IDefense(address(0)), IDefense(address(0)));
        int256 rParanoid = _show("Paranoid", new ParanoidDefense(), new ParanoidDefense());
        int256 rRate2 = _show(
            "RateLimit(cap=2)",
            new RateLimitDefense(2 ether),
            new RateLimitDefense(2 ether)
        );

        assertEq(rNone, 0, "no-defense nets zero");
        assertEq(rParanoid, 0, "paranoid nets zero");
        assertEq(rRate2, 0.75e18, "cap=2 blocks the attack but false-positives the whale");
        assertGt(rRate2, rNone);
        assertGt(rRate2, rParanoid);
    }
}
