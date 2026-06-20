// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LaggedOracleGuard} from "../src/defenses/LaggedOracleGuard.sol";
import {PriceDeviationGuard} from "../src/defenses/PriceDeviationGuard.sol";

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112, uint112, uint32);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

/// @notice Forked-mainnet integration that EXECUTES a real swap on the live
///         Uniswap V2 WETH/USDC pair (rather than only reading reserves and
///         computing): it wraps ETH to WETH, swaps a large amount into the real
///         pool to actually move the on-chain price, and asserts the Aegis price
///         guards react to the genuine pre/post-swap prices. This is the most
///         authentic, least-reproducible data the environment can score — a real
///         single-transaction price manipulation on real mainnet state.
///
///         Gated on MAINNET_RPC_URL; skips cleanly without a fork endpoint so the
///         default `forge test` / CI stays green. Run:
///           MAINNET_RPC_URL=https://ethereum-rpc.publicnode.com \
///           forge test --match-contract ForkSwap -vv
contract ForkSwap is Test {
    address constant PAIR = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc; // USDC(0)/WETH(1)
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function _spot(uint256 reserveUSDC, uint256 reserveWETH) internal pure returns (uint256) {
        return (reserveUSDC * 1e18) / reserveWETH;
    }

    // Uniswap V2 constant-product output, 0.3% fee.
    function _amountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256)
    {
        uint256 inWithFee = amountIn * 997;
        return (inWithFee * reserveOut) / (reserveIn * 1000 + inWithFee);
    }

    function test_real_swap_moves_price_and_guard_reacts() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc);

        (uint112 r0, uint112 r1, ) = IUniswapV2Pair(PAIR).getReserves();
        uint256 reserveUSDC = r0;
        uint256 reserveWETH = r1;
        uint256 preSpot = _spot(reserveUSDC, reserveWETH);

        // Wrap a large amount of ETH and swap WETH -> USDC against the real pool.
        uint256 amountIn = reserveWETH / 2; // +50% of the WETH reserve, one tx
        vm.deal(address(this), amountIn + 1 ether);
        IWETH(WETH).deposit{value: amountIn}();

        uint256 usdcOut = _amountOut(amountIn, reserveWETH, reserveUSDC);
        IWETH(WETH).transfer(PAIR, amountIn);
        IUniswapV2Pair(PAIR).swap(usdcOut, 0, address(this), ""); // amount0Out = USDC

        (uint112 q0, uint112 q1, ) = IUniswapV2Pair(PAIR).getReserves();
        uint256 postSpot = _spot(uint256(q0), uint256(q1));

        emit log_named_uint("pre-swap  spot (1e18)", preSpot);
        emit log_named_uint("post-swap spot (1e18)", postSpot);
        // a real same-block swap genuinely moved the on-chain price
        assertLt(postSpot, preSpot, "swapping WETH in lowers USDC-per-WETH spot");

        // The lagged-oracle guard, comparing the manipulated post price to the
        // pre-swap (start-of-block) price, blocks the action; the genuine pre
        // price passes.
        LaggedOracleGuard lagged = new LaggedOracleGuard(300);
        assertTrue(lagged.authorize(address(0), bytes4(0), 0, abi.encode(preSpot, preSpot)));
        assertFalse(
            lagged.authorize(address(0), bytes4(0), 0, abi.encode(postSpot, preSpot)),
            "lagged guard blocks the real executed manipulation"
        );

        // A fixed anchor at the pre-swap price also flags the real move.
        PriceDeviationGuard fixedGuard = new PriceDeviationGuard(300, preSpot);
        assertFalse(fixedGuard.authorize(address(0), bytes4(0), 0, abi.encode(postSpot, preSpot)));
    }
}
