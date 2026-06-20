// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../interfaces/IDefense.sol";

/// @title MaxVotesGuard — a vote-count threshold defense for Scenario 04.
/// @notice Blocks a proposal execution whose claimed voting power exceeds a fixed
///         cap. This is the natural "anomaly" filter — flag unusually large
///         votes — and it overfits: a cap high enough to admit a legitimate large
///         holder also admits a minimal flash-loan attacker that borrows exactly
///         the quorum (the two are identical by vote count), while a cap low
///         enough to block that attacker false-positives the legitimate holder.
///         It cannot separate borrowed power from held power, because it only
///         sees the count.
contract MaxVotesGuard is IDefense {
    uint256 public immutable maxVotes;

    constructor(uint256 _maxVotes) {
        maxVotes = _maxVotes;
    }

    function authorize(address, bytes4, uint256 votes, bytes calldata) external view returns (bool) {
        return votes <= maxVotes;
    }
}
