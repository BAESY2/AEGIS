// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OracleScenario} from "./base/OracleScenario.sol";

/// @notice Env-driven scorer for Scenario 02 (the gym/sweeps call this).
///   AEGIS_GUARD = none|fixed|lagged, AEGIS_DEVBPS = bps, AEGIS_PUMP = eth
contract Matchup02 is OracleScenario {
    function test_matchup02() public {
        string memory kind = vm.envOr("AEGIS_GUARD", string("none"));
        uint256 devbps = vm.envOr("AEGIS_DEVBPS", uint256(600));
        uint256 pump = vm.envOr("AEGIS_PUMP", uint256(100)) * 1 ether;

        uint256 saved = _savedFraction(kind, devbps, pump);
        uint256 fp = _falsePositives(kind, devbps);
        int256 reward = int256(saved) - int256((fp * 1e18) / BENIGN_TOTAL);

        vm.writeFile(
            "./scoring/matchup02.json",
            string(abi.encodePacked(
                '{"guard":"', kind, '","devbps":', vm.toString(devbps),
                ',"pump_eth":', vm.toString(pump / 1 ether),
                ',"saved_frac_1e18":', vm.toString(saved),
                ',"fp":', vm.toString(fp),
                ',"reward_1e18":', vm.toString(reward), "}"
            ))
        );
    }
}
