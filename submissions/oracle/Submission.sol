// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../../src/interfaces/IDefense.sol";

/// @title Submission (oracle) — drop YOUR oracle-manipulation defense here.
/// @notice Scored with `aegis submit oracle` (or `make submit SCENARIO=oracle`).
///         The oracle scenario passes ctx = abi.encode(spotPrice, laggedPrice).
///         The default below is the lagged-oracle guard (<= 300 bps), a
///         perfect-scoring reference — beat it or match it by another mechanism.
contract Submission is IDefense {
    function authorize(address, bytes4, uint256, bytes calldata ctx) external pure returns (bool) {
        (uint256 spot, uint256 lagged) = abi.decode(ctx, (uint256, uint256));
        if (lagged == 0) return true;
        uint256 diff = spot > lagged ? spot - lagged : lagged - spot;
        return (diff * 10000) / lagged <= 300;
    }
}
