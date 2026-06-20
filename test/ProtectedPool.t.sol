// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProtectedSwapPool} from "../examples/ProtectedSwapPool.sol";
import {PriceImpactGuard} from "../src/defenses/PriceImpactGuard.sol";
import {IDefense} from "../src/interfaces/IDefense.sol";

/// @notice End-to-end proof of the integration pattern: the Aegis hook wired into
///         a real swap path on a minimal constant-product pool. A normal-sized
///         trade passes and moves reserves; a pool-draining trade reverts at the
///         door with AEGIS_BLOCKED — and, crucially, the same pool with NO defense
///         lets the drain through. This is the diff a DEX actually ships.
contract ProtectedPoolTest is Test {
    uint256 constant R0 = 2_000_000_000e6; // 2B USDC (token0, out)
    uint256 constant R1 = 1_000_000 ether; // 1M WETH (token1, in)

    function _pool(IDefense d) internal returns (ProtectedSwapPool) {
        return new ProtectedSwapPool(R0, R1, d);
    }

    function test_normal_trade_passes_and_moves_reserves() public {
        ProtectedSwapPool pool = _pool(new PriceImpactGuard(200)); // 2% cap
        uint256 amountIn = R1 / 1000; // ~0.1% of the pool
        uint256 out = pool.swap(amountIn, 0);
        assertGt(out, 0);
        assertEq(pool.reserve1(), R1 + amountIn);
        assertEq(pool.reserve0(), R0 - out);
    }

    function test_pool_draining_trade_is_blocked_at_the_door() public {
        ProtectedSwapPool pool = _pool(new PriceImpactGuard(200));
        uint256 drain = R1 / 2; // half the pool
        vm.expectRevert(bytes("AEGIS_BLOCKED"));
        pool.swap(drain, 0);
        // reserves untouched: the trade never executed
        assertEq(pool.reserve1(), R1);
        assertEq(pool.reserve0(), R0);
    }

    function test_undefended_pool_lets_the_drain_through() public {
        ProtectedSwapPool pool = _pool(IDefense(address(0)));
        uint256 drain = R1 / 2;
        uint256 out = pool.swap(drain, 0);
        assertGt(out, 0);
        // the undefended pool moved a huge amount of token0 out
        assertLt(pool.reserve0(), R0);
    }
}
