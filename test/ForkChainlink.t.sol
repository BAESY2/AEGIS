// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ChainlinkReferenceGuard} from "../src/defenses/ChainlinkReferenceGuard.sol";

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

/// @notice Forked-mainnet integration using TWO independent real on-chain price
///         sources: the manipulable Uniswap V2 WETH/USDC spot and the trusted
///         Chainlink ETH/USD feed. It executes a real swap to manipulate the
///         Uniswap price, then shows the ChainlinkReferenceGuard passes the
///         genuine spot (close to Chainlink) and blocks the manipulated spot
///         (far from Chainlink) — defense by independent source, on real state.
///         Gated on MAINNET_RPC_URL; skips cleanly without a fork endpoint.
contract ForkChainlink is Test {
    address constant PAIR = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc; // USDC(0)/WETH(1)
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // Chainlink ETH/USD

    function _uniUsd1e18(uint256 reserveUSDC, uint256 reserveWETH) internal pure returns (uint256) {
        // USDC has 6 decimals, WETH 18 -> USD price of WETH, 1e18-scaled.
        return (reserveUSDC * 1e30) / reserveWETH;
    }

    function _uniSpot() internal view returns (uint256) {
        (uint112 r0, uint112 r1, ) = IUniswapV2Pair(PAIR).getReserves();
        return _uniUsd1e18(uint256(r0), uint256(r1));
    }

    function _chainlink() internal view returns (uint256) {
        (, int256 answer, , , ) = IChainlink(FEED).latestRoundData();
        return uint256(answer) * 1e10; // 8-dec feed -> 1e18
    }

    function _manipulate() internal {
        (uint112 r0, uint112 r1, ) = IUniswapV2Pair(PAIR).getReserves();
        uint256 amountIn = uint256(r1) / 2;
        uint256 inWithFee = amountIn * 997;
        uint256 usdcOut = (inWithFee * uint256(r0)) / (uint256(r1) * 1000 + inWithFee);
        vm.deal(address(this), amountIn + 1 ether);
        IWETH(WETH).deposit{value: amountIn}();
        IWETH(WETH).transfer(PAIR, amountIn);
        IUniswapV2Pair(PAIR).swap(usdcOut, 0, address(this), "");
    }

    function test_chainlink_reference_blocks_real_manipulation() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc);

        uint256 ref = _chainlink();
        ChainlinkReferenceGuard guard = new ChainlinkReferenceGuard(1000); // 10%
        emit log_named_uint("chainlink ETH/USD (1e18)", ref);
        emit log_named_uint("uniswap spot pre  (1e18)", _uniSpot());

        // genuine Uniswap spot is close to the Chainlink reference -> allowed
        assertTrue(
            guard.authorize(address(0), bytes4(0), 0, abi.encode(_uniSpot(), ref)),
            "genuine spot agrees with the trusted oracle"
        );

        _manipulate(); // execute a real swap to move the Uniswap price
        emit log_named_uint("uniswap spot post (1e18)", _uniSpot());

        // manipulated spot diverges from the (unmoved) Chainlink feed -> blocked
        assertFalse(
            guard.authorize(address(0), bytes4(0), 0, abi.encode(_uniSpot(), ref)),
            "manipulated spot diverges from the trusted oracle and is blocked"
        );
    }
}
