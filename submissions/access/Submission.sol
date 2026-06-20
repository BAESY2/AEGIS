// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../../src/interfaces/IDefense.sol";

/// @title Submission (access) — drop YOUR access-control defense here.
/// @notice Scored with `aegis submit access`. The access scenario passes
///         ctx = abi.encode(admin). The default below is the authorization
///         invariant (caller must be the admin), a perfect-scoring reference.
contract Submission is IDefense {
    function authorize(address caller, bytes4, uint256, bytes calldata ctx)
        external
        pure
        returns (bool)
    {
        address admin = abi.decode(ctx, (address));
        return caller == admin;
    }
}
