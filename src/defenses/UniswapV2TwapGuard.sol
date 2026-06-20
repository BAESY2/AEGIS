// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../interfaces/IDefense.sol";

interface IUniswapV2PairLike {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price1CumulativeLast() external view returns (uint256);
}

/// @title UniswapV2TwapGuard — time-weighted price integrity from on-chain accumulators.
/// @notice The canonical real-DEX oracle defense. It reads a Uniswap V2 pair's
///         `price1CumulativeLast` accumulator (token0 per token1, UQ112x112) and
///         maintains a stored observation. `authorize` computes the time-weighted
///         average price (TWAP) over the window since the last observation and
///         compares it to the live spot price; it blocks when spot deviates from
///         the TWAP by more than `maxDeviationBps`.
///
///         Manipulation resistance here is intrinsic and distinct from the
///         deviation / lag / cross-venue guards: a flash manipulation moves the
///         *spot* immediately but contributes ~zero seconds to the *time-weighted*
///         average, so an attacker who crashes the pool within a transaction makes
///         spot diverge sharply from the TWAP and is blocked. To actually move the
///         TWAP an attacker must hold the manipulated price across the whole
///         window — economically prohibitive. Validated on live mainnet state in
///         test/ForkTwap.t.sol against the real Uniswap V2 USDC/WETH pool.
///
///         Operational note: `update()` is poked once per window (the standard
///         Uniswap V2 TWAP oracle pattern) to roll the observation forward.
contract UniswapV2TwapGuard is IDefense {
    address public immutable pair;
    uint256 public immutable maxDeviationBps;

    uint256 public observationCumulative; // price1CumulativeLast snapshot (UQ112x112-seconds)
    uint32 public observationTimestamp;

    constructor(address _pair, uint256 _maxDeviationBps) {
        pair = _pair;
        maxDeviationBps = _maxDeviationBps;
        (observationCumulative, observationTimestamp) = _currentCumulative();
    }

    /// @dev price1 cumulative including the pending accrual since the pair's last
    ///      interaction, mirroring Uniswap V2's own oracle reference. price1 is
    ///      token0-per-token1 in UQ112x112: (reserve0 << 112) / reserve1.
    function _currentCumulative() internal view returns (uint256 cum, uint32 ts) {
        (uint112 r0, uint112 r1, uint32 tsLast) = IUniswapV2PairLike(pair).getReserves();
        cum = IUniswapV2PairLike(pair).price1CumulativeLast();
        ts = uint32(block.timestamp);
        uint32 elapsed;
        unchecked {
            elapsed = ts - tsLast; // wrapping subtraction, per Uniswap V2
        }
        if (elapsed > 0 && r1 != 0) {
            uint256 price1Q112 = (uint256(r0) << 112) / uint256(r1);
            cum += price1Q112 * elapsed;
        }
    }

    /// @notice Roll the stored observation forward to now. Poke once per window.
    function update() external {
        (observationCumulative, observationTimestamp) = _currentCumulative();
    }

    /// @return twapQ112 time-weighted average price1 over the observation window (UQ112x112)
    function _twapQ112() internal view returns (uint256 twapQ112) {
        (uint256 cumNow, uint32 tsNow) = _currentCumulative();
        uint32 dt = tsNow - observationTimestamp;
        require(dt > 0, "AEGIS_TWAP_NO_WINDOW");
        twapQ112 = (cumNow - observationCumulative) / dt;
    }

    function _spotQ112() internal view returns (uint256) {
        (uint112 r0, uint112 r1, ) = IUniswapV2PairLike(pair).getReserves();
        if (r1 == 0) return 0;
        return (uint256(r0) << 112) / uint256(r1);
    }

    /// @notice Human-readable USD(1e18) per token1, for off-chain inspection/logging.
    function twapUsd1e18() external view returns (uint256) {
        return (_twapQ112() * 1e30) >> 112;
    }

    function spotUsd1e18() external view returns (uint256) {
        return (_spotQ112() * 1e30) >> 112;
    }

    function authorize(address, bytes4, uint256, bytes calldata) external view returns (bool) {
        uint256 twap = _twapQ112();
        uint256 spot = _spotQ112();
        if (twap == 0) return true;
        uint256 diff = spot > twap ? spot - twap : twap - spot;
        return (diff * 10000) / twap <= maxDeviationBps;
    }
}
