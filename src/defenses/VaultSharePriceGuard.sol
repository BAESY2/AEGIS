// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../interfaces/IDefense.sol";

/// @title VaultSharePriceGuard — bound how fast a vault's share price may rise.
/// @notice The defense the Resupply hack ($9.6M, Jun 2025) lacked and that Inverse
///         FiRM hand-built (Yearn locked-profit accounting). When a protocol values
///         ERC4626 / vault-share collateral by `pricePerShare`, an attacker can
///         DONATE underlying straight to the vault to inflate the share price in a
///         single block, then borrow against the inflated collateral. Real yield
///         accrues *gradually*; a donation spikes the price *instantly*. This guard
///         caps the per-block growth of the reported share price: a donation that
///         jumps it past `maxGrowthBpsPerBlock * elapsedBlocks` is blocked, while
///         normal yield passes.
///
///         ctx = abi.encode(currentPricePerShare). The guard keeps the last
///         accepted (price, block) and only advances its reference on allowed
///         observations, so a rejected spike cannot poison the baseline.
contract VaultSharePriceGuard is IDefense {
    uint256 public immutable maxGrowthBpsPerBlock;
    uint256 public lastPricePerShare;
    uint256 public lastBlock;

    constructor(uint256 _maxGrowthBpsPerBlock, uint256 initialPricePerShare) {
        maxGrowthBpsPerBlock = _maxGrowthBpsPerBlock;
        lastPricePerShare = initialPricePerShare;
        lastBlock = block.number;
    }

    function authorize(address, bytes4, uint256, bytes calldata ctx) external returns (bool) {
        uint256 pps = abi.decode(ctx, (uint256));
        if (lastPricePerShare == 0) {
            lastPricePerShare = pps;
            lastBlock = block.number;
            return true;
        }
        // a falling or flat share price is never a donation-inflation attack
        if (pps <= lastPricePerShare) {
            lastPricePerShare = pps;
            lastBlock = block.number;
            return true;
        }
        uint256 elapsed = block.number - lastBlock;
        uint256 growthBps = ((pps - lastPricePerShare) * 10000) / lastPricePerShare;
        // budget grows with elapsed blocks (+1 so a same-block read still has slack)
        uint256 allowedBps = maxGrowthBpsPerBlock * (elapsed + 1);
        if (growthBps > allowedBps) {
            return false; // instantaneous spike — donation/inflation, do not advance baseline
        }
        lastPricePerShare = pps;
        lastBlock = block.number;
        return true;
    }
}
