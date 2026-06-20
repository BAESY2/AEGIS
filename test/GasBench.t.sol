// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PriceImpactGuard} from "../src/defenses/PriceImpactGuard.sol";
import {CumulativeImpactGuard} from "../src/defenses/CumulativeImpactGuard.sol";
import {MultiSourceConsensusGuard} from "../src/defenses/MultiSourceConsensusGuard.sol";

/// @notice Real per-call gas for the firewall hook — the first question a DEX
///         asks. Measured with gasleft() around the external `authorize` call
///         (so it includes call overhead), separating the stateless guards from
///         the stateful one's cold (new window, 3 SSTOREs from zero) vs warm
///         (window already open) paths. These are checked-in asserts, not claims.
contract GasBench is Test {
    uint256 constant RIN = 1_000_000 ether;
    uint256 constant ROUT = 2_000_000_000e6;

    function _measure(address guard, bytes memory ctx) internal returns (uint256) {
        uint256 g0 = gasleft();
        (bool ok, ) = guard.call(
            abi.encodeWithSignature(
                "authorize(address,bytes4,uint256,bytes)", address(this), bytes4(0), uint256(0), ctx
            )
        );
        uint256 used = g0 - gasleft();
        require(ok, "authorize reverted");
        return used;
    }

    function test_gas_price_impact_stateless() public {
        PriceImpactGuard g = new PriceImpactGuard(200);
        bytes memory ctx = abi.encode(RIN, ROUT, RIN / 1000);
        uint256 used = _measure(address(g), ctx);
        emit log_named_uint("PriceImpactGuard.authorize gas", used);
        assertLt(used, 6000); // stateless, no storage
    }

    function test_gas_consensus_stateless() public {
        MultiSourceConsensusGuard g = new MultiSourceConsensusGuard(500);
        bytes memory ctx = abi.encode(uint256(1723e18), uint256(1722e18), uint256(1724e18));
        uint256 used = _measure(address(g), ctx);
        emit log_named_uint("MultiSourceConsensusGuard.authorize gas", used);
        assertLt(used, 6000);
    }

    function test_gas_cumulative_cold_vs_warm() public {
        CumulativeImpactGuard g = new CumulativeImpactGuard(300, 500);
        bytes memory ctx = abi.encode(RIN, ROUT, RIN / 1000);
        uint256 cold = _measure(address(g), ctx); // opens window: SSTOREs from zero
        uint256 warm = _measure(address(g), ctx); // window already open
        emit log_named_uint("CumulativeImpactGuard.authorize cold gas", cold);
        emit log_named_uint("CumulativeImpactGuard.authorize warm gas", warm);
        // cold path writes new slots; warm path updates an existing one and is cheaper
        assertGt(cold, warm);
        assertLt(warm, 40000);
    }
}
