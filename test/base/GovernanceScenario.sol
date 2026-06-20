// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IDefense} from "../../src/interfaces/IDefense.sol";
import {GovToken} from "../../src/scenarios/governance/GovToken.sol";
import {Governance} from "../../src/scenarios/governance/Governance.sol";
import {FlashGovAttacker} from "../../src/scenarios/governance/FlashGovAttacker.sol";
import {MaxVotesGuard} from "../../src/defenses/MaxVotesGuard.sol";
import {SnapshotVoteGuard} from "../../src/defenses/SnapshotVoteGuard.sol";
import {Submission} from "../../submissions/governance/Submission.sol";

/// @notice Shared measurement core for Scenario 04 (flash-loan governance
///         takeover). The benign actors are legitimate token holders who have
///         held their stake since before the current block and execute ordinary
///         proposals; the attacker flash-borrows voting power within one
///         transaction. A vote-count cap cannot separate a borrowed quorum from a
///         held one; the snapshot invariant can.
abstract contract GovernanceScenario is Test {
    uint256 internal constant TVL = 10 ether;
    uint256 internal constant QUORUM = 100; // votes needed to pass a proposal
    uint256 internal constant BENIGN_TOTAL = 2; // two legitimate holders
    uint256 internal constant HELD_A = 100; // a legitimate quorum-holding voter
    uint256 internal constant HELD_B = 200; // a larger legitimate holder
    uint256 internal constant SPACING = 4;

    /// AEGIS_DEF selects the family for the env-driven matchup scorer:
    ///   "maxvotes" (default) -> MaxVotesGuard(cap)        [vote-count threshold]
    ///   "snapshot"           -> SnapshotVoteGuard()       [structural]
    function _buildDefense(uint256 cap) internal returns (IDefense) {
        bytes32 kind = keccak256(bytes(vm.envOr("AEGIS_DEF", string("maxvotes"))));
        if (kind == keccak256("snapshot")) {
            return new SnapshotVoteGuard();
        }
        if (kind == keccak256("submission")) {
            return new Submission();
        }
        return new MaxVotesGuard(cap);
    }

    function _newGov(IDefense def) internal returns (GovToken token, Governance gov) {
        token = new GovToken();
        gov = new Governance{value: TVL}(token, def, QUORUM);
    }

    function _savedFractionDef(IDefense def, uint256 borrowVotes) internal returns (uint256) {
        (GovToken token, Governance gov) = _newGov(def);
        // advance a block so any prior state is settled before the attack block
        vm.roll(block.number + 1);

        FlashGovAttacker attacker = new FlashGovAttacker(token, gov, borrowVotes);
        attacker.attack(TVL); // attempt to drain the whole treasury

        uint256 remaining = gov.totalAssets();
        return (remaining * 1e18) / TVL; // 1.0 = fully defended, 0.0 = drained
    }

    function _falsePositivesDef(IDefense def) internal returns (uint256 fp) {
        (GovToken token, Governance gov) = _newGov(def);

        address voterA = makeAddr("holderA");
        address voterB = makeAddr("holderB");
        token.mint(voterA, HELD_A);
        token.mint(voterB, HELD_B);

        // legitimate, genuinely-held votes executed in a later block (so prior
        // votes reflect their holdings): a small, ordinary treasury payout each.
        vm.roll(block.number + SPACING);
        vm.prank(voterA);
        try gov.execute(HELD_A, voterA, 1 ether) {} catch {
            fp++;
        }

        vm.roll(block.number + SPACING);
        vm.prank(voterB);
        try gov.execute(HELD_B, voterB, 1 ether) {} catch {
            fp++;
        }
    }

    // env-driven wrappers
    function _savedFraction(uint256 cap, uint256 borrowVotes) internal returns (uint256) {
        return _savedFractionDef(_buildDefense(cap), borrowVotes);
    }

    function _falsePositives(uint256 cap) internal returns (uint256) {
        return _falsePositivesDef(_buildDefense(cap));
    }
}
