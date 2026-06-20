// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {GovernanceScenario} from "./base/GovernanceScenario.sol";
import {IDefense} from "../src/interfaces/IDefense.sol";
import {Reward} from "../src/lib/Reward.sol";
import {MaxVotesGuard} from "../src/defenses/MaxVotesGuard.sol";
import {SnapshotVoteGuard} from "../src/defenses/SnapshotVoteGuard.sol";

/// @notice Static scoreboard for Scenario 04, asserting the frontier:
///   - the undefended governor is drained by a flash-borrowed quorum;
///   - a vote-count cap cannot both pass legitimate holders AND stop a minimal
///     flash attacker that borrows exactly the quorum (identical by count);
///   - the snapshot invariant stops every flash loan, at any borrow size, with
///     zero false positives.
contract GovernanceScoreboard is GovernanceScenario {
    function test_undefended_is_drained() public {
        IDefense none = new MaxVotesGuard(type(uint256).max); // cap so high it never trips
        assertEq(_savedFractionDef(none, QUORUM), 0, "minimal flash quorum drains it");
        assertEq(_savedFractionDef(none, 5000), 0, "large flash loan drains it");
    }

    function test_vote_cap_overfits() public {
        // A cap that admits the legitimate large holder (HELD_B = 200)...
        IDefense cap250 = new MaxVotesGuard(250);
        assertEq(_falsePositivesDef(cap250), 0, "passes both legitimate holders");
        // ...also admits a minimal attacker borrowing exactly the quorum.
        assertEq(_savedFractionDef(new MaxVotesGuard(250), QUORUM), 0, "minimal flash attacker slips through");

        // A cap low enough to block that attacker now false-positives holders.
        assertGt(_falsePositivesDef(new MaxVotesGuard(QUORUM - 1)), 0, "blocking the attacker harms holders");
    }

    function test_snapshot_crosses_floor() public {
        // structural defense: flash-borrowed votes are not backed by prior
        // holdings -> blocked at every borrow size.
        assertEq(_savedFractionDef(new SnapshotVoteGuard(), QUORUM), 1e18, "minimal flash blocked");
        assertEq(_savedFractionDef(new SnapshotVoteGuard(), 5000), 1e18, "large flash blocked");
        // ...and genuinely-held votes are never blocked.
        uint256 fp = _falsePositivesDef(new SnapshotVoteGuard());
        assertEq(fp, 0, "legitimate holders served");

        int256 reward = Reward.score(true, fp, BENIGN_TOTAL);
        assertEq(reward, 1e18, "perfect: stops takeover, zero false positives");
    }
}
