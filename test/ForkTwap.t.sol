// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {UniswapV2TwapGuard} from "../src/defenses/UniswapV2TwapGuard.sol";

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112, uint112, uint32);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

/// @notice Forked-mainnet integration for the time-weighted (TWAP) oracle guard.
///         It builds a TWAP observation over a real 30-minute window on the live
///         Uniswap V2 USDC/WETH pool, then executes a real swap to crash the spot
///         price within a single block, and shows the guard allows the genuine
///         (spot == TWAP) state and blocks once spot diverges from the time-
///         weighted average. A flash manipulation cannot move a TWAP it only
///         touched for an instant. Gated on MAINNET_RPC_URL; skips without it.
contract ForkTwap is Test {
    address constant UNI = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc; // USDC(0)/WETH(1)
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function _manipulateUni() internal {
        (uint112 r0, uint112 r1, ) = IUniswapV2Pair(UNI).getReserves();
        uint256 amountIn = uint256(r1) / 2;
        uint256 inWithFee = amountIn * 997;
        uint256 usdcOut = (inWithFee * uint256(r0)) / (uint256(r1) * 1000 + inWithFee);
        vm.deal(address(this), amountIn + 1 ether);
        IWETH(WETH).deposit{value: amountIn}();
        IWETH(WETH).transfer(UNI, amountIn);
        IUniswapV2Pair(UNI).swap(usdcOut, 0, address(this), "");
    }

    function test_twap_blocks_flash_manipulation() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc);

        // observation starts now; build a genuine 30-minute TWAP window
        UniswapV2TwapGuard guard = new UniswapV2TwapGuard(UNI, 500); // 5%
        vm.warp(block.timestamp + 1800);

        emit log_named_uint("twap (usd 1e18)", guard.twapUsd1e18());
        emit log_named_uint("spot (usd 1e18)", guard.spotUsd1e18());

        // genuine price: spot tracks the TWAP -> allowed
        assertTrue(
            guard.authorize(address(0), bytes4(0), 0, ""),
            "genuine spot matches the time-weighted average"
        );

        _manipulateUni(); // crash spot within this block
        emit log_named_uint("spot post (usd 1e18)", guard.spotUsd1e18());
        emit log_named_uint("twap post (usd 1e18)", guard.twapUsd1e18());

        // a flash manipulation moves spot but not the TWAP -> blocked
        assertFalse(
            guard.authorize(address(0), bytes4(0), 0, ""),
            "spot diverged from the TWAP after a flash manipulation and is blocked"
        );
    }
}
