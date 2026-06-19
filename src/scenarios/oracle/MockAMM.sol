// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MockAMM — a constant-product pool used as a price source.
/// @notice Accounting-only (no token transfers). `spotPrice` is instantaneously
///         manipulable by a swap — the vulnerability scenario 02 exploits.
///         It also exposes `laggedPrice`: the price as of the start of the
///         current block, snapshotted before this block's first swap. That is a
///         one-block-lagged oracle a defense can use to resist *same-block*
///         manipulation of any size, while still tracking genuine multi-block
///         price drift.
contract MockAMM {
    uint256 public reserveEth;
    uint256 public reserveTok;
    uint256 public laggedPrice; // price at the start of the current block
    uint256 public lastObsBlock;

    constructor(uint256 e, uint256 t) {
        reserveEth = e;
        reserveTok = t;
        laggedPrice = spotPrice();
        lastObsBlock = block.number;
    }

    function spotPrice() public view returns (uint256) {
        return (reserveEth * 1e18) / reserveTok; // ETH per TOKEN, 1e18-scaled
    }

    /// Refresh the lagged price for the current block (idempotent per block).
    function poke() external {
        _poke();
    }

    function _poke() internal {
        // Snapshot the pre-swap price once per block, so `laggedPrice` can never
        // reflect manipulation performed within the current block.
        if (block.number > lastObsBlock) {
            laggedPrice = spotPrice();
            lastObsBlock = block.number;
        }
    }

    function swapEthForTok(uint256 ethIn) external returns (uint256 tokOut) {
        _poke();
        uint256 k = reserveEth * reserveTok;
        uint256 newEth = reserveEth + ethIn;
        uint256 newTok = k / newEth;
        tokOut = reserveTok - newTok;
        reserveEth = newEth;
        reserveTok = newTok;
    }

    function swapTokForEth(uint256 tokIn) external returns (uint256 ethOut) {
        _poke();
        uint256 k = reserveEth * reserveTok;
        uint256 newTok = reserveTok + tokIn;
        uint256 newEth = k / newTok;
        ethOut = reserveEth - newEth;
        reserveEth = newEth;
        reserveTok = newTok;
    }
}
