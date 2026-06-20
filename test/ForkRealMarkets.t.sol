// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PriceImpactGuard} from "../src/defenses/PriceImpactGuard.sol";
import {UniswapV2TwapGuard} from "../src/defenses/UniswapV2TwapGuard.sol";

interface IPair {
    function getReserves() external view returns (uint112, uint112, uint32);
}

/// @notice The precision half of the story, on real data: the manipulation tests
///         show the guards BLOCK an attack; this shows they do NOT block genuine
///         market activity across several diverse, live Uniswap V2 pools. A
///         normal-sized trade and an unmanipulated spot (== TWAP) must pass on
///         every real pool — low false positives on real liquidity, not a mock.
///         Gated on MAINNET_RPC_URL; skips without it.
contract ForkRealMarkets is Test {
    address[4] PAIRS = [
        0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc, // USDC/WETH
        0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11, // DAI/WETH
        0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852, // WETH/USDT
        0xBb2b8038a1640196FbE3e38816F3e67Cba72D940 // WBTC/WETH
    ];

    function _impactAllows(PriceImpactGuard impact, address pair) internal view returns (bool) {
        (uint112 r0, uint112 r1, ) = IPair(pair).getReserves();
        uint256 amountIn = uint256(r1) / 2000; // ~0.05% of the pool
        return impact.authorize(
            address(0), bytes4(0), 0, abi.encode(uint256(r1), uint256(r0), amountIn)
        );
    }

    function _twapAllows(address pair) internal returns (bool) {
        UniswapV2TwapGuard g = new UniswapV2TwapGuard(pair, 100); // 1%
        vm.warp(block.timestamp + 1800); // genuine 30-min window, no manipulation
        return g.authorize(address(0), bytes4(0), 0, "");
    }

    function test_guards_allow_genuine_markets() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc);

        PriceImpactGuard impact = new PriceImpactGuard(100); // 1% cap

        for (uint256 i = 0; i < PAIRS.length; i++) {
            address pair = PAIRS[i];
            assertTrue(_impactAllows(impact, pair), "normal trade must pass on a genuine pool");
            assertTrue(_twapAllows(pair), "unmanipulated spot tracks the TWAP on a genuine pool");
        }
    }
}
