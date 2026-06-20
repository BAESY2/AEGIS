// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessScenario} from "./base/AccessScenario.sol";
import {IDefense} from "../src/interfaces/IDefense.sol";
import {Reward} from "../src/lib/Reward.sol";
import {WindowedRateLimitDefense} from "../src/defenses/WindowedRateLimitDefense.sol";
import {OwnerOnlyDefense} from "../src/defenses/OwnerOnlyDefense.sol";

/// @notice Static scoreboard for Scenario 03, asserting the frontier:
///   - the undefended treasury is drained at every pace;
///   - a value/rate cap low enough to slow a patient attacker false-positives
///     the legitimate admin whale (and a patient attacker still evades it);
///   - the identity-based OwnerOnly defense stops every unauthorized drain at
///     every pace with zero false positives.
contract AccessScoreboard is AccessScenario {
    uint256 constant HORIZON = 12;

    function _none() internal returns (IDefense) {
        return new WindowedRateLimitDefense(1, 1000 ether); // cap so high it never trips
    }

    function test_undefended_is_drained() public {
        assertEq(_savedFractionDef(_none(), 2 ether, HORIZON), 0, "patient drain empties it");
        assertEq(_savedFractionDef(_none(), 11 ether, HORIZON), 0, "greedy drain empties it");
    }

    function test_rate_cap_overfits() public {
        IDefense cap5 = new WindowedRateLimitDefense(1, 5 ether);
        // A tight windowed cap (5 ether/block) stops the greedy one-shot drain...
        assertGt(_savedFractionDef(cap5, 11 ether, HORIZON), 0, "cap stops the greedy attacker");
        // ...but a patient attacker draining 2 ether/block stays under it and
        // still empties the treasury.
        assertEq(
            _savedFractionDef(new WindowedRateLimitDefense(1, 5 ether), 2 ether, HORIZON),
            0,
            "patient attacker evades the cap"
        );
    }

    function test_owneronly_crosses_floor() public {
        // structural defense: attacker is never the admin -> blocked at every pace
        assertEq(_savedFractionDef(new OwnerOnlyDefense(), 2 ether, HORIZON), 1e18, "patient blocked");
        assertEq(_savedFractionDef(new OwnerOnlyDefense(), 11 ether, HORIZON), 1e18, "greedy blocked");
        // ...and the legitimate admin is never blocked, including the whale
        uint256 fp = _falsePositivesDef(new OwnerOnlyDefense());
        assertEq(fp, 0, "admin served perfectly");

        int256 reward = Reward.score(true, fp, BENIGN_TOTAL);
        assertEq(reward, 1e18, "perfect: stops attack, zero false positives");
    }
}
