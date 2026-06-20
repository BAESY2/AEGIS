// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IDefense} from "../src/interfaces/IDefense.sol";
import {SmartAccount} from "../src/scenarios/behavioral/SmartAccount.sol";
import {AmountThresholdDefense} from "../src/defenses/AmountThresholdDefense.sol";
import {NewDestinationDefense} from "../src/defenses/NewDestinationDefense.sol";
import {BehavioralDefense} from "../src/defenses/BehavioralDefense.sol";

/// @notice Scenario 05 scoreboard — the "no free lunch" frontier.
///
/// Unlike every other scenario, the structural authorization invariant is
/// useless here (the thief holds the owner's key), and legitimate/malicious
/// behavior genuinely overlap, so NO defense reaches perfect recall at zero
/// false positives. We score a precision/recall frontier and assert:
///   - the authorization invariant catches zero attacks;
///   - a feature-combining (learned-shape) defense DOMINATES single-feature
///     thresholds on the operating metric (TPR - FPR);
///   - yet it cannot reach (TPR=1, FPR=0): catching the patient thief who mimics
///     a legitimate new-payee payment necessarily costs false positives.
contract BehavioralScoreboard is Test {
    address internal owner = makeAddr("owner");

    // Owner's legitimate behavior (amount in ether, destination is "known"):
    // mostly known payees and moderate amounts, with two ambiguous-but-honest
    // habits — one large payment to a known payee, two small payments to NEW payees.
    function _legit() internal pure returns (uint256[8] memory amt, bool[8] memory known) {
        amt = [uint256(1), 2, 1, 3, 1, 2, 1, 1];
        known = [true, true, true, true, false, true, true, false];
    }

    // The thief draining the account — all to fresh addresses; the last two are
    // a "patient" thief mimicking a small legitimate new-payee payment.
    function _attack() internal pure returns (uint256[6] memory amt, bool[6] memory known) {
        amt = [uint256(5), 5, 4, 3, 2, 1];
        known = [false, false, false, false, false, false];
    }

    function _blocked(IDefense def, uint256 amountEth, bool toKnown, uint256 salt)
        internal
        returns (bool)
    {
        SmartAccount a = new SmartAccount{value: 20 ether}(def, owner);
        address dest = address(uint160(uint256(keccak256(abi.encode("dest", salt)))));
        if (toKnown) a.markKnown(dest);
        vm.prank(owner);
        try a.withdraw(amountEth * 1 ether, dest) {
            return false;
        } catch {
            return true;
        }
    }

    /// Returns (falsePositives out of 8 legit, truePositives out of 6 attacks).
    function _score(IDefense def) internal returns (uint256 fp, uint256 tp) {
        (uint256[8] memory la, bool[8] memory lk) = _legit();
        for (uint256 i = 0; i < 8; i++) {
            if (_blocked(def, la[i], lk[i], 1000 + i)) fp++;
        }
        (uint256[6] memory aa, bool[6] memory ak) = _attack();
        for (uint256 i = 0; i < 6; i++) {
            if (_blocked(def, aa[i], ak[i], 2000 + i)) tp++;
        }
    }

    function _reward(uint256 fp, uint256 tp) internal pure returns (int256) {
        // Youden's J in 1e18: TPR - FPR
        return int256((tp * 1e18) / 6) - int256((fp * 1e18) / 8);
    }

    function test_no_free_lunch_frontier() public {
        vm.deal(address(this), 100000 ether);

        (uint256 fpNone, uint256 tpNone) = _score(IDefense(address(0)));
        (uint256 fpAmt, uint256 tpAmt) = _score(new AmountThresholdDefense(2 ether));
        (uint256 fpAmtHi, uint256 tpAmtHi) = _score(new AmountThresholdDefense(4 ether));
        (uint256 fpNew, uint256 tpNew) = _score(new NewDestinationDefense());
        (uint256 fpBeh, uint256 tpBeh) = _score(new BehavioralDefense(2 ether));

        console2.log("defense            FP/8  TP/6  reward(1e18)");
        _row("none (owner-only)", fpNone, tpNone);
        _row("amount<=2", fpAmt, tpAmt);
        _row("amount<=4", fpAmtHi, tpAmtHi);
        _row("new-destination", fpNew, tpNew);
        _row("behavioral", fpBeh, tpBeh);

        // 1) The authorization invariant (owner check) catches zero attacks: the
        //    thief is the owner. Structure is useless here.
        assertEq(tpNone, 0, "owner-only catches no attacks (stolen key)");
        assertEq(fpNone, 0);

        // 2) The feature-combining defense DOMINATES single-feature thresholds on
        //    the operating metric (TPR - FPR).
        int256 rBeh = _reward(fpBeh, tpBeh);
        assertGt(rBeh, _reward(fpAmt, tpAmt), "behavioral beats amount<=2");
        assertGt(rBeh, _reward(fpAmtHi, tpAmtHi), "behavioral beats amount<=4");
        assertGt(rBeh, _reward(fpNew, tpNew), "behavioral beats new-destination");
        assertGt(rBeh, int256(0));

        // 3) NO FREE LUNCH: the behavioral defense reaches zero false positives
        //    but cannot catch every attack (the patient thief mimicking a small
        //    new-payee payment is indistinguishable)...
        assertEq(fpBeh, 0, "behavioral has zero false positives");
        assertLt(tpBeh, 6, "behavioral cannot catch the indistinguishable thief");

        // ...and the only defense that catches every attack pays false positives.
        assertEq(tpNew, 6, "new-destination catches all attacks");
        assertGt(fpNew, 0, "...but false-positives legitimate new payees");

        // 4) Therefore no tested defense achieves perfect recall at zero FP.
        assertFalse(tpNone == 6 && fpNone == 0);
        assertFalse(tpAmt == 6 && fpAmt == 0);
        assertFalse(tpAmtHi == 6 && fpAmtHi == 0);
        assertFalse(tpNew == 6 && fpNew == 0);
        assertFalse(tpBeh == 6 && fpBeh == 0);
    }

    function _row(string memory name, uint256 fp, uint256 tp) internal pure {
        console2.log(name);
        console2.log("   FP:", fp, " TP:", tp);
        console2.logInt(_reward(fp, tp));
    }
}
