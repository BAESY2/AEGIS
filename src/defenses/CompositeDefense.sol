// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../interfaces/IDefense.sol";

/// @title CompositeDefense — defense composition as a first-class primitive.
/// @notice Stacks N defenses sharing a scenario's ctx into one. This is what
///         turns the benchmark from a handful of hand-written defenses into a
///         combinatorial space: with P compatible primitives there are 2^P
///         possible stacks, each with its own parameter settings, multiplying the
///         configuration space by orders of magnitude (see `aegis space`).
///
///         mode ALL (defense-in-depth): allow only if EVERY member allows — block
///         if any member blocks. This is how real protocols layer controls.
///         mode ANY (lenient / fallback): allow if ANY member allows.
///
///         All members must decode the SAME scenario ctx; composing across
///         scenarios is undefined. Members may be stateful — each is invoked once
///         per protected call, in order.
contract CompositeDefense is IDefense {
    IDefense[] internal members;
    bool public immutable requireAll;

    constructor(IDefense[] memory _members, bool _requireAll) {
        members = _members;
        requireAll = _requireAll;
    }

    function size() external view returns (uint256) {
        return members.length;
    }

    function authorize(address caller, bytes4 selector, uint256 value, bytes calldata ctx)
        external
        returns (bool)
    {
        uint256 n = members.length;
        if (requireAll) {
            for (uint256 i = 0; i < n; i++) {
                if (!members[i].authorize(caller, selector, value, ctx)) return false;
            }
            return true;
        } else {
            for (uint256 i = 0; i < n; i++) {
                if (members[i].authorize(caller, selector, value, ctx)) return true;
            }
            return n == 0; // empty OR-stack is permissive (no constraint)
        }
    }
}
