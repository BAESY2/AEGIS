// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IDefense} from "../src/interfaces/IDefense.sol";
import {PriceDeviationGuard} from "../src/defenses/PriceDeviationGuard.sol";
import {LaggedOracleGuard} from "../src/defenses/LaggedOracleGuard.sol";

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

/// @notice Forked-mainnet integration for Scenario 02 (oracle manipulation),
///         run against REAL on-chain state rather than a mock AMM. It forks
///         Ethereum mainnet, reads the live reserves of the Uniswap V2
///         WETH/USDC pair, derives the real spot price, computes a realistic
///         single-transaction manipulation from those real reserves (constant
///         product), and asserts that the same Aegis price guards behave as the
///         local scenario predicts — on real magnitudes, not toy 1e18 values.
///
///         This is the bridge from synthetic to non-reproducible data: each run
///         reads whatever the pool's reserves actually are. It is gated on
///         MAINNET_RPC_URL and skips cleanly when no RPC is configured, so the
///         default `forge test` (and CI) stays green without a fork endpoint.
///
///         Run it with:
///           MAINNET_RPC_URL=https://ethereum-rpc.publicnode.com \
///           forge test --match-contract ForkOracle -vv
contract ForkOracle is Test {
    // Uniswap V2 WETH/USDC pair (token0 = USDC[6], token1 = WETH[18]).
    address constant PAIR = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;

    function _spot(uint256 reserveUSDC, uint256 reserveWETH) internal pure returns (uint256) {
        // Scale-invariant ratio (the guards compare relative deviation in bps).
        return (reserveUSDC * 1e18) / reserveWETH;
    }

    function test_realPair_guards_behave() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true); // no fork endpoint configured — skip (not a failure)
            return;
        }
        vm.createSelectFork(rpc);

        (uint112 r0, uint112 r1, ) = IUniswapV2Pair(PAIR).getReserves();
        uint256 reserveUSDC = uint256(r0);
        uint256 reserveWETH = uint256(r1);
        assertGt(reserveUSDC, 0);
        assertGt(reserveWETH, 0);

        uint256 realSpot = _spot(reserveUSDC, reserveWETH);
        emit log_named_uint("real WETH/USDC spot (1e18-scaled)", realSpot);

        // A realistic same-block manipulation: an attacker swaps `pump` USDC into
        // the real pool; new price follows the real constant product k = x*y.
        uint256 pump = reserveUSDC / 2; // +50% of USDC reserve in one swap
        uint256 k = reserveUSDC * reserveWETH;
        uint256 newUSDC = reserveUSDC + pump;
        uint256 newWETH = k / newUSDC;
        uint256 manipSpot = _spot(newUSDC, newWETH);
        assertGt(manipSpot, realSpot, "pump must move spot up");

        // Fixed-anchor guard anchored at the real spot: passes the real price,
        // blocks the manipulated one.
        PriceDeviationGuard fixedGuard = new PriceDeviationGuard(300, realSpot);
        assertTrue(
            fixedGuard.authorize(address(0), bytes4(0), 0, abi.encode(realSpot, realSpot)),
            "real spot is within tolerance of its own anchor"
        );
        assertFalse(
            fixedGuard.authorize(address(0), bytes4(0), 0, abi.encode(manipSpot, realSpot)),
            "fixed guard blocks the real-reserve manipulation"
        );

        // Lagged-oracle guard (lagged = real start-of-block spot) blocks the
        // same-block manipulation regardless of size, with no false positive on
        // the genuine price.
        LaggedOracleGuard lagged = new LaggedOracleGuard(300);
        assertTrue(
            lagged.authorize(address(0), bytes4(0), 0, abi.encode(realSpot, realSpot)),
            "lagged guard passes the genuine price"
        );
        assertFalse(
            lagged.authorize(address(0), bytes4(0), 0, abi.encode(manipSpot, realSpot)),
            "lagged guard blocks the same-block manipulation on real state"
        );
    }
}
