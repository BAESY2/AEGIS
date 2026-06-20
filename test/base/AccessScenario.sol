// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IDefense} from "../../src/interfaces/IDefense.sol";
import {Treasury} from "../../src/scenarios/access/Treasury.sol";
import {UnauthorizedDrainer} from "../../src/scenarios/access/UnauthorizedDrainer.sol";
import {WindowedRateLimitDefense} from "../../src/defenses/WindowedRateLimitDefense.sol";
import {OwnerOnlyDefense} from "../../src/defenses/OwnerOnlyDefense.sol";
import {Submission} from "../../submissions/access/Submission.sol";

/// @notice Shared measurement core for Scenario 03 (broken access control).
///         The benign actor is the legitimate admin, performing several small
///         withdrawals plus one large ("whale") one — so a value/rate cap set
///         low enough to slow the attacker also false-positives the admin,
///         while an identity-based defense serves the admin perfectly and stops
///         every unauthorized drain regardless of pacing.
///
///         Measurement takes an explicit `IDefense` so static tests never rely
///         on process-global env vars (which leak across forge test cases). The
///         env-driven matchup wraps these via `_buildDefense`.
abstract contract AccessScenario is Test {
    uint256 internal constant TVL = 10 ether;
    uint256 internal constant WHALE = 4 ether; // one large, legitimate admin withdrawal
    uint256 internal constant BENIGN_TOTAL = 4; // 3 small admin ops + 1 whale
    uint256 internal constant SPACING = 16; // legit ops land in separate windows

    address internal admin = makeAddr("admin");

    /// AEGIS_DEF selects the family for the env-driven matchup scorer:
    ///   "windowed" (default) -> WindowedRateLimitDefense(window, cap)  [value/rate]
    ///   "owneronly"          -> OwnerOnlyDefense()                     [structural]
    function _buildDefense(uint256 W, uint256 cap) internal returns (IDefense) {
        string memory kind = vm.envOr("AEGIS_DEF", string("windowed"));
        if (keccak256(bytes(kind)) == keccak256(bytes("owneronly"))) {
            return new OwnerOnlyDefense();
        }
        if (keccak256(bytes(kind)) == keccak256(bytes("submission"))) {
            return new Submission();
        }
        return new WindowedRateLimitDefense(W, cap);
    }

    function _fund(Treasury t) internal {
        vm.deal(address(this), TVL);
        t.fund{value: TVL}();
    }

    // ---- explicit-defense measurement (used by static tests) ----
    function _savedFractionDef(IDefense def, uint256 take, uint256 horizon)
        internal
        returns (uint256 savedFrac1e18)
    {
        Treasury t = new Treasury(def, admin);
        _fund(t);

        UnauthorizedDrainer attacker = new UnauthorizedDrainer(t, take);
        for (uint256 b = 0; b < horizon; b++) {
            attacker.pulse();
            vm.roll(block.number + 1);
        }

        uint256 stolen = address(attacker).balance;
        if (stolen >= TVL) return 0;
        return ((TVL - stolen) * 1e18) / TVL;
    }

    function _falsePositivesDef(IDefense def) internal returns (uint256 fp) {
        Treasury t = new Treasury(def, admin);
        _fund(t);

        for (uint256 i = 0; i < 3; i++) {
            vm.roll(block.number + SPACING);
            vm.prank(admin);
            try t.adminWithdraw(1 ether, admin) {} catch {
                fp++;
            }
        }
        // one large, perfectly legitimate admin withdrawal
        vm.roll(block.number + SPACING);
        vm.prank(admin);
        try t.adminWithdraw(WHALE, admin) {} catch {
            fp++;
        }
    }

    // ---- env-driven measurement (used by the matchup scorer) ----
    function _savedFraction(uint256 W, uint256 cap, uint256 take, uint256 horizon)
        internal
        returns (uint256)
    {
        return _savedFractionDef(_buildDefense(W, cap), take, horizon);
    }

    function _falsePositives(uint256 W, uint256 cap) internal returns (uint256) {
        return _falsePositivesDef(_buildDefense(W, cap));
    }
}
