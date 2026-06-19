// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OracleScenario} from "./base/OracleScenario.sol";
import {IDefense} from "../src/interfaces/IDefense.sol";

/// @notice Static scoreboard for Scenario 02, asserting the frontier:
///   - the undefended pool is exploitable at every pump size;
///   - a fixed-anchor guard cannot both pass organic drift AND stop a small
///     same-block pump of equal magnitude (the floor);
///   - a lagged-oracle guard crosses that floor: stops all pumps, zero FPs.
contract OracleScoreboard is OracleScenario {
    function test_exploitable_undefended() public {
        // excess borrow exists for every pump => the oracle bug is real
        assertGt(_excess(IDefense(address(0)), 3 ether), 0);
        assertGt(_excess(IDefense(address(0)), 100 ether), 0);
    }

    function test_fixed_anchor_floor() public {
        // tuned to pass organic drift (fp=0) -> loses to the small pump (saved 0)
        assertEq(_savedFraction("fixed", 609, 3 ether), 0, "small pump mimics drift");
        assertEq(_falsePositives("fixed", 609), 0, "passes organic at 609bps");

        // tightened to catch the small pump -> now false-positives organic drift
        assertEq(_savedFraction("fixed", 300, 3 ether), 1e18, "300bps catches pump=3");
        assertEq(_falsePositives("fixed", 300), 1, "but blocks the organic borrow");
    }

    function test_lagged_oracle_crosses_floor() public {
        // stops same-block manipulation of any size, with zero false positives
        assertEq(_savedFraction("lagged", 300, 3 ether), 1e18);
        assertEq(_savedFraction("lagged", 300, 100 ether), 1e18); // big pump too
        assertEq(_falsePositives("lagged", 300), 0);
    }
}
