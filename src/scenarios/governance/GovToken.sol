// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title GovToken — a minimal governance token with a one-block-lagged snapshot.
/// @notice Accounting-only (no transfers needed for the scenario). `balanceOf` is
///         the instantaneous voting power — manipulable within a transaction by
///         minting (modeling a flash loan of governance tokens). `priorVotes`
///         returns the balance as of the START of the current block, snapshotted
///         lazily before this block's first balance change — so it can never
///         reflect tokens acquired within the current block. That is the signal a
///         snapshot-based defense uses to ignore flash-borrowed votes while still
///         counting genuinely held stake.
contract GovToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) private _snapBal;
    mapping(address => uint256) private _snapBlock;

    function _poke(address a) internal {
        // Snapshot the pre-change balance once per block, so `priorVotes` reflects
        // start-of-block holdings regardless of same-block mints/burns.
        if (_snapBlock[a] != block.number) {
            _snapBal[a] = balanceOf[a];
            _snapBlock[a] = block.number;
        }
    }

    /// Voting power as of the start of the current block.
    function priorVotes(address a) external view returns (uint256) {
        return _snapBlock[a] == block.number ? _snapBal[a] : balanceOf[a];
    }

    function mint(address a, uint256 amt) external {
        _poke(a);
        balanceOf[a] += amt;
    }

    function burn(address a, uint256 amt) external {
        _poke(a);
        balanceOf[a] -= amt;
    }
}
