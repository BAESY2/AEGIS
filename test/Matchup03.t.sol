// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessScenario} from "./base/AccessScenario.sol";

/// @notice Env-driven scorer for Scenario 03 (broken access control). The gym /
///         benchmark sweeps call this with:
///   AEGIS_DEF = windowed|owneronly, AEGIS_WINDOW, AEGIS_CAP (eth),
///   AEGIS_TAKE (eth/block), AEGIS_HORIZON
contract Matchup03 is AccessScenario {
    function test_matchup03() public {
        uint256 W = vm.envOr("AEGIS_WINDOW", uint256(1));
        uint256 cap = vm.envOr("AEGIS_CAP", uint256(5)) * 1 ether;
        uint256 take = vm.envOr("AEGIS_TAKE", uint256(11)) * 1 ether;
        uint256 horizon = vm.envOr("AEGIS_HORIZON", uint256(12));

        uint256 saved = _savedFraction(W, cap, take, horizon);
        uint256 fp = _falsePositives(W, cap);
        int256 reward = int256(saved) - int256((fp * 1e18) / BENIGN_TOTAL);

        string memory json = string(
            abi.encodePacked(
                '{"window":', vm.toString(W),
                ',"cap_eth":', vm.toString(cap / 1 ether),
                ',"take_eth":', vm.toString(take / 1 ether),
                ',"horizon":', vm.toString(horizon),
                ',"saved_frac_1e18":', vm.toString(saved),
                ',"fp":', vm.toString(fp),
                ',"reward_1e18":', vm.toString(reward), "}"
            )
        );
        vm.writeFile("./scoring/matchup03.json", json);
    }
}
