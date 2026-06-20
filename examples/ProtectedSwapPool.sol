// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../src/interfaces/IDefense.sol";

/// @title ProtectedSwapPool — a minimal constant-product pool with the Aegis hook.
/// @notice A reference integration showing the *one line* a DEX adds to protect a
///         swap path. The pool itself is intentionally minimal (a textbook x*y=k
///         AMM with a 0.30% fee); what matters is the firewall hook at the top of
///         `swap`, which asks a pluggable `IDefense` whether to allow the trade
///         before any state changes. Point `defense` at any Aegis guard (e.g.
///         PriceImpactGuard) and oversized / manipulative trades revert at the
///         door while normal trades pass. See test/ProtectedPool.t.sol.
contract ProtectedSwapPool {
    uint256 public reserve0; // token0 (the "out" side here)
    uint256 public reserve1; // token1 (the "in" side here)
    IDefense public defense;

    bytes4 public constant SWAP_SELECTOR = bytes4(keccak256("swap(uint256,uint256)"));

    constructor(uint256 r0, uint256 r1, IDefense _defense) {
        reserve0 = r0;
        reserve1 = r1;
        defense = _defense;
    }

    /// @notice Swap `amountIn` of token1 for token0 (constant product, 0.30% fee).
    /// @return amountOut token0 returned.
    function swap(uint256 amountIn, uint256 minOut) external returns (uint256 amountOut) {
        // ---- Aegis firewall hook (the one line a DEX adds) ----
        if (address(defense) != address(0)) {
            bool allow = defense.authorize(
                msg.sender,
                SWAP_SELECTOR,
                amountIn,
                abi.encode(reserve1, reserve0, amountIn) // (reserveIn, reserveOut, amountIn)
            );
            require(allow, "AEGIS_BLOCKED");
        }
        // -------------------------------------------------------

        uint256 amountInWithFee = amountIn * 997;
        amountOut = (amountInWithFee * reserve0) / (reserve1 * 1000 + amountInWithFee);
        require(amountOut >= minOut, "SLIPPAGE");

        reserve1 += amountIn;
        reserve0 -= amountOut;
    }
}
