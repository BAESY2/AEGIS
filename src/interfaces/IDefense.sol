// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IDefense — the interface every Aegis defense submission implements.
/// @notice A protected protocol calls `authorize` at the top of each sensitive
///         action (a single-line "firewall hook"). The defense returns `true`
///         to ALLOW the action or `false` to BLOCK it (the protocol reverts).
///
///         A submission is scored by HOW WELL `authorize` separates real
///         attacks (which it should block) from legitimate traffic (which it
///         must let through). Blocking everything is not a winning strategy —
///         see src/lib/Reward.sol.
interface IDefense {
    /// @param caller   The address invoking the protected action (tx-level msg.sender of the protocol call).
    /// @param selector The function selector of the protected action.
    /// @param value    The economic magnitude of the action (e.g. withdrawal amount, in wei).
    /// @param ctx      ABI-encoded, scenario-specific context snapshot.
    /// @return allow   True to allow, false to block.
    function authorize(
        address caller,
        bytes4 selector,
        uint256 value,
        bytes calldata ctx
    ) external returns (bool allow);
}
