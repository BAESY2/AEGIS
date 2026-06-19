// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../interfaces/IDefense.sol";

/// @title ParanoidDefense — the "block everything" strawman.
/// @notice Stops every attack perfectly... and every legitimate user too.
///         Exists to demonstrate that the reward function is NOT gameable by
///         blanket blocking: full attack-block reward is exactly cancelled by a
///         100% false-positive penalty, netting ~0 — no better than no defense.
contract ParanoidDefense is IDefense {
    function authorize(address, bytes4, uint256, bytes calldata) external pure returns (bool) {
        return false;
    }
}
