// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../../src/interfaces/IDefense.sol";

/// @title Submission (behavioral) — drop YOUR stolen-key/behavioral defense here.
/// @notice Scored with `aegis submit behavioral`. The behavioral scenario passes
///         ctx = abi.encode(amount, isNewDestination). There is no perfect
///         defense for this class (see the no-free-lunch result); the default
///         below is a materiality rule (block a >= 2 ETH transfer to a new
///         destination) — a strong operating point. Try to dominate it.
contract Submission is IDefense {
    function authorize(address, bytes4, uint256, bytes calldata ctx) external pure returns (bool) {
        (uint256 amount, bool isNew) = abi.decode(ctx, (uint256, bool));
        if (isNew && amount >= 2 ether) return false;
        return true;
    }
}
