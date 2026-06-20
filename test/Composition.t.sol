// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IDefense} from "../src/interfaces/IDefense.sol";
import {CompositeDefense} from "../src/defenses/CompositeDefense.sol";

contract _AllowAll is IDefense {
    function authorize(address, bytes4, uint256, bytes calldata) external pure returns (bool) {
        return true;
    }
}

contract _BlockAll is IDefense {
    function authorize(address, bytes4, uint256, bytes calldata) external pure returns (bool) {
        return false;
    }
}

/// @notice Composition semantics — the primitive that makes the configuration
///         space combinatorial (2^N stacks of N defenses; see `aegis space`).
contract CompositionTest is Test {
    function _stack(bool a, bool b, bool requireAll) internal returns (bool) {
        IDefense[] memory ms = new IDefense[](2);
        ms[0] = a ? IDefense(new _AllowAll()) : IDefense(new _BlockAll());
        ms[1] = b ? IDefense(new _AllowAll()) : IDefense(new _BlockAll());
        return new CompositeDefense(ms, requireAll).authorize(address(0), bytes4(0), 0, "");
    }

    function test_and_blocks_if_any_member_blocks() public {
        // defense-in-depth: allow only if ALL allow
        assertTrue(_stack(true, true, true));
        assertFalse(_stack(true, false, true));
        assertFalse(_stack(false, true, true));
        assertFalse(_stack(false, false, true));
    }

    function test_or_allows_if_any_member_allows() public {
        // fallback: allow if ANY allows
        assertTrue(_stack(true, true, false));
        assertTrue(_stack(true, false, false));
        assertTrue(_stack(false, true, false));
        assertFalse(_stack(false, false, false));
    }

    function test_size() public {
        IDefense[] memory ms = new IDefense[](3);
        ms[0] = new _AllowAll();
        ms[1] = new _AllowAll();
        ms[2] = new _BlockAll();
        assertEq(new CompositeDefense(ms, true).size(), 3);
    }
}
