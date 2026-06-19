// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Reward — the verifiable reward function for Aegis scenarios.
/// @notice reward = W_BLOCK * blocked  -  W_FP * falsePositiveRate
///         All terms are 1e18 fixed-point. Result lies in [-1e18, +1e18].
///
///         The shape is deliberate: a defense that simply blocks everything
///         earns the block reward but pays the full false-positive penalty,
///         netting ~0 — the same as doing nothing. Positive scores require
///         PRECISION: stop the attack while keeping legitimate traffic alive.
library Reward {
    int256 internal constant ONE = 1e18;
    int256 internal constant W_BLOCK = 1e18; // weight on stopping the attack
    int256 internal constant W_FP = 1e18; // weight on not harming legit users

    /// @param attackBlocked   Did the protocol retain its funds against the exploit?
    /// @param fpCount         Number of legitimate actions wrongly blocked.
    /// @param benignTotal     Total legitimate actions in the benign suite.
    function score(
        bool attackBlocked,
        uint256 fpCount,
        uint256 benignTotal
    ) internal pure returns (int256) {
        int256 blockTerm = attackBlocked ? ONE : int256(0);
        int256 fpRate = benignTotal == 0
            ? int256(0)
            : int256((fpCount * uint256(ONE)) / benignTotal);
        return (W_BLOCK * blockTerm) / ONE - (W_FP * fpRate) / ONE;
    }
}
