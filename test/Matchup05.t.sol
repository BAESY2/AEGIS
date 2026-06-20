// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IDefense} from "../src/interfaces/IDefense.sol";
import {SmartAccount} from "../src/scenarios/behavioral/SmartAccount.sol";
import {AmountThresholdDefense} from "../src/defenses/AmountThresholdDefense.sol";
import {NewDestinationDefense} from "../src/defenses/NewDestinationDefense.sol";
import {BehavioralDefense} from "../src/defenses/BehavioralDefense.sol";
import {CompositeDefense} from "../src/defenses/CompositeDefense.sol";

/// @notice Env-driven scorer for Scenario 05 (behavioral / stolen key) over an
///         ATTACKER-STEALTH axis. Unlike the other matchups, the label here is
///         genuinely ambiguous: as the attacker mixes in more "stealth"
///         withdrawals (small amount to a new address, indistinguishable from a
///         legitimate new-payee payment), the achievable recall falls and the
///         best defense CHANGES — a behavioral materiality rule wins at low
///         stealth, a block-all-new rule wins at high stealth. There is no single
///         best defense and no clean reward>0 boundary, which is exactly the
///         hard-label regime an active learner needs.
///
///   AEGIS_DEF     = none|amount|behavioral|newdest (or '+'-joined composite)
///   AEGIS_CAP     = amount cap (ether)        [for the amount filter]
///   AEGIS_MAT     = materiality floor (ether) [for the behavioral filter]
///   AEGIS_STEALTH = 0..100  (fraction of attacks that are stealthy)
///
///   reward = saved - fp/benign, where saved = attacks blocked / attacks total
///   (recall), fp = legitimate withdrawals blocked, benign = legit total (8).
contract Matchup05 is Test {
    address internal owner = makeAddr("owner");
    uint256 internal constant LEGIT = 8;
    uint256 internal constant ATTACKS = 6;

    function _member(string memory kind, uint256 capEth, uint256 matEth) internal returns (IDefense) {
        bytes32 k = keccak256(bytes(kind));
        if (k == keccak256("amount")) return new AmountThresholdDefense(capEth * 1 ether);
        if (k == keccak256("behavioral")) return new BehavioralDefense(matEth * 1 ether);
        if (k == keccak256("newdest")) return new NewDestinationDefense();
        return IDefense(address(0)); // "none"
    }

    function _build(uint256 capEth, uint256 matEth) internal returns (IDefense) {
        string[] memory parts = _split(vm.envOr("AEGIS_DEF", string("behavioral")), "+");
        if (parts.length == 1) return _member(parts[0], capEth, matEth);
        // composite of the non-"none" members
        IDefense[] memory tmp = new IDefense[](parts.length);
        uint256 n = 0;
        for (uint256 i = 0; i < parts.length; i++) {
            IDefense m = _member(parts[i], capEth, matEth);
            if (address(m) != address(0)) tmp[n++] = m;
        }
        if (n == 0) return IDefense(address(0));
        if (n == 1) return tmp[0];
        IDefense[] memory ms = new IDefense[](n);
        for (uint256 i = 0; i < n; i++) ms[i] = tmp[i];
        return new CompositeDefense(ms, true);
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

    function _score(IDefense def, uint256 stealth) internal returns (uint256 fp, uint256 tp) {
        uint256[8] memory la = [uint256(1), 2, 1, 3, 1, 2, 1, 1];
        bool[8] memory lk = [true, true, true, true, false, true, true, false];
        for (uint256 i = 0; i < LEGIT; i++) {
            if (_blocked(def, la[i], lk[i], 1000 + i)) fp++;
        }
        uint256 nStealth = (stealth * ATTACKS) / 100;
        for (uint256 i = 0; i < ATTACKS; i++) {
            uint256 amt = i < nStealth ? 1 : 5; // stealth: small to new; greedy: large to new
            if (_blocked(def, amt, false, 2000 + i)) tp++;
        }
    }

    function test_matchup05() public {
        vm.deal(address(this), 100000 ether);
        uint256 cap = vm.envOr("AEGIS_CAP", uint256(2));
        uint256 mat = vm.envOr("AEGIS_MAT", uint256(2));
        uint256 stealth = vm.envOr("AEGIS_STEALTH", uint256(50));

        (uint256 fp, uint256 tp) = _score(_build(cap, mat), stealth);
        uint256 saved = (tp * 1e18) / ATTACKS;
        int256 reward = int256(saved) - int256((fp * 1e18) / LEGIT);

        vm.writeFile(
            "./scoring/matchup05.json",
            string(abi.encodePacked(
                '{"stealth":', vm.toString(stealth),
                ',"cap":', vm.toString(cap), ',"mat":', vm.toString(mat),
                ',"saved_frac_1e18":', vm.toString(saved),
                ',"fp":', vm.toString(fp),
                ',"reward_1e18":', vm.toString(reward), "}"
            ))
        );
    }

    function _split(string memory s, bytes1 sep) internal pure returns (string[] memory parts) {
        bytes memory b = bytes(s);
        uint256 count = 1;
        for (uint256 i = 0; i < b.length; i++) if (b[i] == sep) count++;
        parts = new string[](count);
        uint256 start = 0;
        uint256 idx = 0;
        for (uint256 i = 0; i <= b.length; i++) {
            if (i == b.length || b[i] == sep) {
                bytes memory part = new bytes(i - start);
                for (uint256 j = start; j < i; j++) part[j - start] = b[j];
                parts[idx++] = string(part);
                start = i + 1;
            }
        }
    }
}
