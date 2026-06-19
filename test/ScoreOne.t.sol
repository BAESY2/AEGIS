// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console2} from "forge-std/Test.sol";
import {ReentrancyScenario} from "./base/ReentrancyScenario.sol";

/// @notice Single-configuration scorer, driven by the AEGIS_CAP env var (in
///         ether). This is the bridge the gym calls: Python sets a candidate
///         cap, this evaluates it on-chain, and the execution-derived reward is
///         written to scoring/run.json for the agent to read.
contract ScoreOne is ReentrancyScenario {
    function test_scoreOne() public {
        uint256 capEth = vm.envOr("AEGIS_CAP", uint256(2));
        uint256 capWei = capEth * 1 ether;

        (int256 reward, bool blocked, uint256 fp) = _evaluateCap(capWei);

        string memory json = string(
            abi.encodePacked(
                '{"cap_eth":', vm.toString(capEth),
                ',"reward_1e18":', vm.toString(reward),
                ',"attack_blocked":', blocked ? "true" : "false",
                ',"false_positives":', vm.toString(fp),
                ',"benign_total":', vm.toString(BENIGN_TOTAL), "}"
            )
        );
        vm.writeFile("./scoring/run.json", json);

        console2.log("cap(eth):", capEth, " reward(1e18):");
        console2.logInt(reward);
    }
}
