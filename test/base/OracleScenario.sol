// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IDefense} from "../../src/interfaces/IDefense.sol";
import {MockAMM} from "../../src/scenarios/oracle/MockAMM.sol";
import {LendingPool} from "../../src/scenarios/oracle/LendingPool.sol";
import {OracleManipAttacker} from "../../src/scenarios/oracle/OracleManipAttacker.sol";
import {PriceDeviationGuard} from "../../src/defenses/PriceDeviationGuard.sol";
import {LaggedOracleGuard} from "../../src/defenses/LaggedOracleGuard.sol";

/// @notice Shared measurement core for Scenario 02 (oracle/price manipulation).
abstract contract OracleScenario is Test {
    uint256 internal constant E0 = 100 ether;
    uint256 internal constant T0 = 100 ether;
    uint256 internal constant COLL = 10 ether;
    uint256 internal constant FAIR = 1e18;
    uint256 internal constant ORGANIC_SWAP = 3 ether; // ~6.09% organic drift
    uint256 internal constant BENIGN_TOTAL = 2;

    function _guard(string memory kind, uint256 devbps) internal returns (IDefense) {
        bytes32 k = keccak256(bytes(kind));
        if (k == keccak256("fixed")) return new PriceDeviationGuard(devbps, FAIR);
        if (k == keccak256("lagged")) return new LaggedOracleGuard(devbps);
        return IDefense(address(0));
    }

    function _excess(IDefense def, uint256 pump) internal returns (uint256) {
        MockAMM amm = new MockAMM(E0, T0);
        LendingPool pool = new LendingPool(amm, def);
        OracleManipAttacker atk = new OracleManipAttacker();
        try atk.attack(amm, pool, pump, COLL) {} catch {}
        uint256 borrowed = pool.totalBorrowed();
        uint256 fair = pool.fairMaxBorrow(address(atk));
        return borrowed > fair ? borrowed - fair : 0;
    }

    function _savedFraction(string memory kind, uint256 devbps, uint256 pump)
        internal
        returns (uint256)
    {
        uint256 baseline = _excess(IDefense(address(0)), pump);
        if (baseline == 0) return 1e18;
        uint256 defended = _excess(_guard(kind, devbps), pump);
        return defended >= baseline ? 0 : ((baseline - defended) * 1e18) / baseline;
    }

    function _falsePositives(string memory kind, uint256 devbps) internal returns (uint256 fp) {
        {
            MockAMM amm = new MockAMM(E0, T0);
            LendingPool pool = new LendingPool(amm, _guard(kind, devbps));
            address u = makeAddr("fairUser");
            pool.depositCollateral(u, COLL);
            vm.prank(u);
            try pool.borrow(1 ether) {} catch { fp++; }
        }
        {
            MockAMM amm = new MockAMM(E0, T0);
            LendingPool pool = new LendingPool(amm, _guard(kind, devbps));
            amm.swapEthForTok(ORGANIC_SWAP);
            vm.roll(block.number + 1);
            address u = makeAddr("driftUser");
            pool.depositCollateral(u, COLL);
            vm.prank(u);
            try pool.borrow(1 ether) {} catch { fp++; }
        }
    }
}
