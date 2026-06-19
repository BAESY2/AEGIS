// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDefense} from "../../interfaces/IDefense.sol";
import {MockAMM} from "./MockAMM.sol";

/// @title LendingPool — Scenario 02 target.
/// @notice Values collateral at the AMM SPOT price (the bug) and lends up to
///         LTV against it. The one-line firewall hook lets a defense inspect the
///         price context at borrow time. `fairPrice` is the reference captured
///         at deploy; protocol loss is borrowing enabled beyond what the fair
///         price would allow.
contract LendingPool {
    MockAMM public immutable amm;
    IDefense public immutable defense;
    uint256 public constant LTV = 50; // percent
    uint256 public immutable fairPrice;
    uint256 public totalBorrowed;
    mapping(address => uint256) public collateralTok;

    constructor(MockAMM _amm, IDefense _def) {
        amm = _amm;
        defense = _def;
        fairPrice = _amm.spotPrice();
    }

    function depositCollateral(address who, uint256 tok) external {
        collateralTok[who] += tok;
    }

    function borrow(uint256 ethAmount) external returns (bool) {
        amm.poke(); // settle the lagged oracle for this block
        uint256 price = amm.spotPrice();

        // ---- Aegis firewall hook ----
        if (address(defense) != address(0)) {
            bool allow = defense.authorize(
                msg.sender,
                msg.sig,
                ethAmount,
                abi.encode(price, amm.laggedPrice())
            );
            require(allow, "AEGIS_BLOCKED");
        }
        // -----------------------------

        uint256 collateralValue = (collateralTok[msg.sender] * price) / 1e18;
        uint256 maxBorrow = (collateralValue * LTV) / 100;
        require(ethAmount <= maxBorrow, "undercollateralized");
        totalBorrowed += ethAmount;
        return true;
    }

    /// Borrowing the fair price would have permitted for `who`.
    function fairMaxBorrow(address who) external view returns (uint256) {
        return (((collateralTok[who] * fairPrice) / 1e18) * LTV) / 100;
    }
}
