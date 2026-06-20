// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MultiSourceConsensusGuard} from "../src/defenses/MultiSourceConsensusGuard.sol";

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112, uint112, uint32);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IChainlink {
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
}

/// @notice Forked-mainnet integration using THREE independent real price sources
///         — Uniswap V2, Sushiswap, and the Chainlink ETH/USD feed. It executes a
///         real swap to manipulate the Uniswap price and shows the
///         MultiSourceConsensusGuard passes when all three agree and blocks when
///         one venue is manipulated away from the others. Cross-venue price
///         integrity, on real state. Gated on MAINNET_RPC_URL; skips without it.
contract ForkConsensus is Test {
    address constant UNI = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc; // USDC(0)/WETH(1)
    address constant SUSHI = 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0; // USDC(0)/WETH(1)
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    function _usd(address pair) internal view returns (uint256) {
        (uint112 r0, uint112 r1, ) = IUniswapV2Pair(pair).getReserves();
        return (uint256(r0) * 1e30) / uint256(r1); // USDC(6)/WETH(18) -> USD 1e18
    }

    function _chainlink() internal view returns (uint256) {
        (, int256 answer, , , ) = IChainlink(FEED).latestRoundData();
        return uint256(answer) * 1e10;
    }

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

    function test_consensus_blocks_single_venue_manipulation() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc);

        uint256 chainlink = _chainlink();
        MultiSourceConsensusGuard guard = new MultiSourceConsensusGuard(500); // 5%
        emit log_named_uint("uniswap   (1e18)", _usd(UNI));
        emit log_named_uint("sushiswap (1e18)", _usd(SUSHI));
        emit log_named_uint("chainlink (1e18)", chainlink);

        // all three venues agree -> allowed
        assertTrue(
            guard.authorize(address(0), bytes4(0), 0, abi.encode(_usd(UNI), _usd(SUSHI), chainlink)),
            "independent sources agree on the genuine price"
        );

        _manipulateUni(); // manipulate one venue with a real swap
        emit log_named_uint("uniswap post (1e18)", _usd(UNI));

        // the manipulated venue is now an outlier -> blocked
        assertFalse(
            guard.authorize(address(0), bytes4(0), 0, abi.encode(_usd(UNI), _usd(SUSHI), chainlink)),
            "a single manipulated venue breaks consensus and is blocked"
        );
    }
}
