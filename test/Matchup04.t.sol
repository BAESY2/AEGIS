// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {GovernanceScenario} from "./base/GovernanceScenario.sol";

/// @notice Env-driven scorer for Scenario 04 (flash-loan governance takeover).
///   AEGIS_DEF = maxvotes|snapshot, AEGIS_CAP (vote cap), AEGIS_TAKE (borrow votes)
contract Matchup04 is GovernanceScenario {
    function test_matchup04() public {
        uint256 cap = vm.envOr("AEGIS_CAP", uint256(250));
        uint256 borrow = vm.envOr("AEGIS_TAKE", uint256(1000));

        uint256 saved = _savedFraction(cap, borrow);
        uint256 fp = _falsePositives(cap);
        int256 reward = int256(saved) - int256((fp * 1e18) / BENIGN_TOTAL);

        string memory json = string(
            abi.encodePacked(
                '{"cap":', vm.toString(cap),
                ',"borrow_votes":', vm.toString(borrow),
                ',"saved_frac_1e18":', vm.toString(saved),
                ',"fp":', vm.toString(fp),
                ',"reward_1e18":', vm.toString(reward), "}"
            )
        );
        vm.writeFile("./scoring/matchup04.json", json);
    }
}
