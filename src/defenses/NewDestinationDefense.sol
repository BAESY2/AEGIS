// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../interfaces/IDefense.sol";

/// @title NewDestinationDefense — the other single-feature filter (Scenario 05).
/// @notice Blocks any withdrawal to a destination the owner has never used. It
///         catches EVERY thief that exfiltrates to a fresh address (perfect
///         recall) — but false-positives the owner the moment they legitimately
///         pay a new payee. It sits at the opposite corner of the frontier from
///         a pure amount cap: maximal recall, non-zero false positives. Together
///         with the amount filter it shows that no single feature, and no
///         feature combination, reaches perfect recall at zero false positives.
contract NewDestinationDefense is IDefense {
    function authorize(address, bytes4, uint256, bytes calldata ctx) external pure returns (bool) {
        (, bool isNew) = abi.decode(ctx, (uint256, bool));
        return !isNew;
    }
}
