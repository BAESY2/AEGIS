// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../interfaces/IDefense.sol";

/// @title PriceDeviationGuard — a fixed-anchor price guard for scenario 02.
/// @notice Blocks a borrow when the spot price deviates from a fixed reference
///         beyond `maxDeviationBps`. ctx = abi.encode(spotPrice, laggedPrice);
///         this guard ignores the lagged price and compares spot to the anchor
///         set at construction (the fair price). Its weakness — demonstrated in
///         the scenario — is that it cannot distinguish a small same-block pump
///         from genuine multi-block drift of the same magnitude.
contract PriceDeviationGuard is IDefense {
    uint256 public immutable maxDeviationBps;
    uint256 public immutable anchor;

    constructor(uint256 _maxDeviationBps, uint256 _anchor) {
        maxDeviationBps = _maxDeviationBps;
        anchor = _anchor;
    }

    function authorize(address, bytes4, uint256, bytes calldata ctx) external view returns (bool) {
        (uint256 spot, ) = abi.decode(ctx, (uint256, uint256));
        uint256 diff = spot > anchor ? spot - anchor : anchor - spot;
        return (diff * 10000) / anchor <= maxDeviationBps;
    }
}
