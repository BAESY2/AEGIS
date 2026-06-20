// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../interfaces/IDefense.sol";

/// @title ChainlinkReferenceGuard — block when a manipulable spot price diverges
///        from an INDEPENDENT trusted oracle (e.g. a Chainlink feed).
/// @notice ctx = abi.encode(spotPrice, referencePrice), both same-scaled. The
///         guard blocks the action when spot deviates from the reference beyond
///         `maxDeviationBps`. Unlike the lagged-oracle guard (which resists
///         same-block manipulation in time), this resists it in SOURCE: an
///         attacker who moves one venue's price cannot move an independent
///         oracle in the same transaction, so a manipulated AMM spot shows a
///         large divergence from the reference and is blocked, while a genuine
///         price (close to the reference) passes. Demonstrated on real mainnet
///         state in test/ForkChainlink.t.sol against the live Chainlink ETH/USD
///         feed.
contract ChainlinkReferenceGuard is IDefense {
    uint256 public immutable maxDeviationBps;

    constructor(uint256 _maxDeviationBps) {
        maxDeviationBps = _maxDeviationBps;
    }

    function authorize(address, bytes4, uint256, bytes calldata ctx) external view returns (bool) {
        (uint256 spot, uint256 ref) = abi.decode(ctx, (uint256, uint256));
        if (ref == 0) return true;
        uint256 diff = spot > ref ? spot - ref : ref - spot;
        return (diff * 10000) / ref <= maxDeviationBps;
    }
}
