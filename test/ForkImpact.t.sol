// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PriceImpactGuard} from "../src/defenses/PriceImpactGuard.sol";

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112, uint112, uint32);
}

/// @notice Forked-mainnet integration for the liquidity-aware price-impact guard.
///         Using the LIVE reserves of the Uniswap V2 USDC/WETH pool, it shows the
///         guard allows a normal-sized swap (small market footprint) and blocks a
///         pool-draining swap — the same half-pool swap the oracle fork tests use
///         to crash the price. Bounds a trade's own impact relative to real
///         liquidity. Gated on MAINNET_RPC_URL; skips without it.
contract ForkImpact is Test {
    address constant UNI = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc; // USDC(0)/WETH(1)

    function test_impact_blocks_pool_draining_swap() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc);

        // WETH(token1) in, USDC(token0) out
        (uint112 r0, uint112 r1, ) = IUniswapV2Pair(UNI).getReserves();
        uint256 reserveIn = uint256(r1); // WETH
        uint256 reserveOut = uint256(r0); // USDC

        PriceImpactGuard guard = new PriceImpactGuard(200); // 2% cap

        uint256 small = reserveIn / 1000; // ~0.1% of the pool
        uint256 huge = reserveIn / 2; // half the pool — a flash drain

        emit log_named_uint("small swap impact (bps)", guard.impactBps(reserveIn, reserveOut, small));
        emit log_named_uint("huge swap impact  (bps)", guard.impactBps(reserveIn, reserveOut, huge));

        assertTrue(
            guard.authorize(address(0), bytes4(0), 0, abi.encode(reserveIn, reserveOut, small)),
            "a normal-sized swap has small market impact and is allowed"
        );
        assertFalse(
            guard.authorize(address(0), bytes4(0), 0, abi.encode(reserveIn, reserveOut, huge)),
            "a pool-draining swap exceeds the impact cap and is blocked"
        );
    }
}
