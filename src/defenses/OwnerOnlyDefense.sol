// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../interfaces/IDefense.sol";

/// @title OwnerOnlyDefense — the structural defense for Scenario 03.
/// @notice Restores the authorization invariant the target forgot: a privileged
///         action may only be performed by the configured admin. It reads the
///         admin from ctx = abi.encode(admin) and allows the call iff the caller
///         is that admin — ignoring the amount entirely.
///
///         Because it enforces *identity*, not a value/rate threshold, it stops
///         every unauthorized drain regardless of how the attacker paces it, and
///         never blocks a legitimate admin operation of any size. This crosses
///         the floor a value/rate-based filter hits (where a patient attacker
///         draining at "normal" amounts is indistinguishable from the admin by
///         amount alone) — the same structural-beats-threshold pattern as the
///         reentrancy and oracle scenarios, in the access-control class.
contract OwnerOnlyDefense is IDefense {
    function authorize(address caller, bytes4, uint256, bytes calldata ctx)
        external
        pure
        returns (bool)
    {
        address admin = abi.decode(ctx, (address));
        return caller == admin;
    }
}
