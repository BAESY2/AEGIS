// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../interfaces/IDefense.sol";

/// @title SnapshotVoteGuard — the structural defense for Scenario 04.
/// @notice Requires that claimed voting power be backed by the caller's
///         start-of-block (prior) holdings, not by tokens acquired within the
///         current block. ctx = abi.encode(priorVotes, currentVotes); the guard
///         allows the action iff votes <= priorVotes.
///
///         A single-block flash loan cannot move `priorVotes`, so a flash-borrowed
///         quorum (priorVotes ≈ 0) is blocked at ANY borrow size, while a
///         genuinely held quorum passes untouched. This is the real-world fix
///         (Compound/OZ Governor snapshot voting) and it crosses the floor the
///         vote-count threshold hits: it enforces an invariant ("you must have
///         held the stake before this block") rather than fitting a count
///         threshold, so it generalizes across the whole attacker family with
///         zero false positives.
contract SnapshotVoteGuard is IDefense {
    function authorize(address, bytes4, uint256 votes, bytes calldata ctx)
        external
        pure
        returns (bool)
    {
        (uint256 priorVotes, ) = abi.decode(ctx, (uint256, uint256));
        return votes <= priorVotes;
    }
}
