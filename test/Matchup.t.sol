// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {Reward} from "../src/lib/Reward.sol";
import {VulnerableVault} from "../src/scenarios/reentrancy/VulnerableVault.sol";
import {PatientReentrancyAttacker} from "../src/scenarios/reentrancy/PatientReentrancyAttacker.sol";
import {WindowedRateLimitDefense} from "../src/defenses/WindowedRateLimitDefense.sol";
import {PerAddressInvariantDefense} from "../src/defenses/PerAddressInvariantDefense.sol";
import {ReentrancyLockDefense} from "../src/defenses/ReentrancyLockDefense.sol";
import {CompositeDefense} from "../src/defenses/CompositeDefense.sol";
import {IDefense} from "../src/interfaces/IDefense.sol";

/// @notice Env-driven co-evolution matchup scorer. Evaluates one
///         (defender = (window, cap)) vs (attacker = takePerBlock) pairing over
///         a fixed response horizon, plus a legitimate-traffic suite, and emits
///         saved-fraction / false-positives / reward to scoring/matchup.json.
contract Matchup is Test {
    uint256 constant TVL = 10 ether;
    uint256 constant CHUNK = 1 ether; // attacker seed
    uint256 constant WHALE = 4 ether;
    uint256 constant BENIGN_TOTAL = 4;
    uint256 constant SPACING = 16; // legit events land in separate windows

    /// Build the defense under test. AEGIS_DEF selects the family, and may be a
    /// '+'-joined COMPOSITE (defense-in-depth) of compatible primitives:
    ///   "windowed" -> WindowedRateLimitDefense(window, cap)  [rate]
    ///   "peraddr"  -> PerAddressInvariantDefense()           [structural]
    ///   "lock"     -> ReentrancyLockDefense()                [structural]
    ///   e.g. "windowed+peraddr" -> CompositeDefense([rate, structural], requireAll)
    /// The 2^N stacks of N primitives are what make the configuration space
    /// combinatorial (see `aegis space`).
    function _member(string memory kind, uint256 W, uint256 cap) internal returns (IDefense) {
        bytes32 k = keccak256(bytes(kind));
        if (k == keccak256("peraddr")) return new PerAddressInvariantDefense();
        if (k == keccak256("lock")) return new ReentrancyLockDefense();
        return new WindowedRateLimitDefense(W, cap);
    }

    function _buildDefense(uint256 W, uint256 cap) internal returns (IDefense) {
        string[] memory parts = _split(vm.envOr("AEGIS_DEF", string("windowed")), "+");
        if (parts.length == 1) return _member(parts[0], W, cap);
        IDefense[] memory ms = new IDefense[](parts.length);
        for (uint256 i = 0; i < parts.length; i++) ms[i] = _member(parts[i], W, cap);
        return new CompositeDefense(ms, true); // defense-in-depth: block if any blocks
    }

    function _split(string memory s, bytes1 sep) internal pure returns (string[] memory parts) {
        bytes memory b = bytes(s);
        uint256 count = 1;
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] == sep) count++;
        }
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

    function _savedFraction(uint256 W, uint256 cap, uint256 take, uint256 horizon)
        internal
        returns (uint256 savedFrac1e18)
    {
        IDefense def = _buildDefense(W, cap);
        VulnerableVault vault = new VulnerableVault(def);

        address victim = makeAddr("victim");
        vm.deal(victim, TVL);
        vm.prank(victim);
        vault.deposit{value: TVL}();

        PatientReentrancyAttacker attacker = new PatientReentrancyAttacker(vault, take);
        vm.deal(address(this), CHUNK);
        attacker.seed{value: CHUNK}();

        for (uint256 b = 0; b < horizon; b++) {
            try attacker.pulse() {} catch {}
            vm.roll(block.number + 1);
        }

        uint256 extracted = address(attacker).balance; // ETH the attacker holds
        uint256 victimLoss = extracted > CHUNK ? extracted - CHUNK : 0; // beyond its own seed
        if (victimLoss >= TVL) return 0;
        return ((TVL - victimLoss) * 1e18) / TVL;
    }

    function _falsePositives(uint256 W, uint256 cap) internal returns (uint256 fp) {
        IDefense def = _buildDefense(W, cap);
        VulnerableVault vault = new VulnerableVault(def);

        for (uint256 i = 0; i < 3; i++) {
            address u = makeAddr(string(abi.encodePacked("retail", i)));
            vm.deal(u, CHUNK);
            vm.prank(u);
            vault.deposit{value: CHUNK}();
            vm.roll(block.number + SPACING);
            vm.prank(u);
            try vault.withdraw(CHUNK) {} catch { fp++; }
        }
        address whale = makeAddr("whale");
        vm.deal(whale, WHALE);
        vm.prank(whale);
        vault.deposit{value: WHALE}();
        vm.roll(block.number + SPACING);
        vm.prank(whale);
        try vault.withdraw(WHALE) {} catch { fp++; }
    }

    function test_matchup() public {
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
        vm.writeFile("./scoring/matchup.json", json);
    }
}
