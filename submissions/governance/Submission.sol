// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../../src/interfaces/IDefense.sol";

/// @title Submission (governance) — drop YOUR flash-loan-governance defense here.
/// @notice Scored with `aegis submit governance`. The governance scenario passes
///         ctx = abi.encode(priorVotes, currentVotes). The default below is the
///         snapshot invariant (votes must be backed by prior-block holdings), a
///         perfect-scoring reference.
contract Submission is IDefense {
    function authorize(address, bytes4, uint256 votes, bytes calldata ctx)
        external
        pure
        returns (bool)
    {
        (uint256 priorVotes, ) = abi.decode(ctx, (uint256, uint256));
        return votes <= priorVotes;
    }
}
