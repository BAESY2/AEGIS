// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../../interfaces/IDefense.sol";

/// @title Treasury — Scenario 03 target (broken access control).
/// @notice A protocol treasury whose privileged `adminWithdraw` is MISSING its
///         access-control check — the single most common cause of real on-chain
///         losses (unprotected admin / init / migration functions). Any address
///         can call it and drain the treasury.
///
///         The only security-relevant line a real protocol adds is the Aegis
///         firewall hook. The scenario asks: can a defense stop the
///         unauthorized drain while still letting the *legitimate* admin operate
///         (including large, perfectly valid withdrawals)?
///
///         The hook receives ctx = abi.encode(admin), so an identity-aware
///         defense can enforce the authorization invariant the target forgot,
///         while a value/rate-based defense sees only the amount.
contract Treasury {
    IDefense public immutable defense;
    address public immutable admin;

    constructor(IDefense _defense, address _admin) {
        defense = _defense;
        admin = _admin;
    }

    function fund() external payable {}

    /// VULNERABLE: no `require(msg.sender == admin)`. The authorization check
    /// the developer forgot is exactly what a structural defense restores.
    function adminWithdraw(uint256 amount, address to) external {
        require(address(this).balance >= amount, "insufficient");

        // ---- Aegis firewall hook (the one line a protocol integrates) ----
        if (address(defense) != address(0)) {
            bool allow = defense.authorize(msg.sender, msg.sig, amount, abi.encode(admin));
            require(allow, "AEGIS_BLOCKED");
        }
        // ------------------------------------------------------------------

        (bool ok, ) = to.call{value: amount}("");
        require(ok, "transfer failed");
    }

    function totalAssets() external view returns (uint256) {
        return address(this).balance;
    }

    receive() external payable {}
}
