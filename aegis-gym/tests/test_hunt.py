"""Tests for the oracle manipulation-cost model, calibrated to a real exploit."""
import unittest

from aegis import hunt


class TestHunt(unittest.TestCase):
    def test_calibrated_to_inverse_finance(self):
        # The Inverse Finance hack moved the SushiSwap INV/WETH pool ~56x by
        # pushing ~300 WETH into a ~46 WETH reserve. The model should agree.
        frac = hunt.manipulation_cost_fraction(56)
        predicted_weth = 46 * frac
        self.assertAlmostEqual(predicted_weth, 300, delta=15)

    def test_doubling_cost_is_root2_minus_1(self):
        self.assertAlmostEqual(hunt.manipulation_cost_fraction(2.0), 2 ** 0.5 - 1, places=9)
        self.assertEqual(hunt.manipulation_cost_fraction(1.0), 0.0)
        self.assertEqual(hunt.manipulation_cost_fraction(0.5), 0.0)

    def test_assess_flags_thin_pool_securing_large_value(self):
        a = hunt.assess(pool_liquidity_usd=1_000_000, secured_value_usd=10_000_000, move_factor=2.0)
        self.assertTrue(a["profitable"])
        self.assertGreater(a["ratio_secured_to_cost"], 1)

    def test_assess_marks_deep_pool_safe(self):
        a = hunt.assess(pool_liquidity_usd=500_000_000, secured_value_usd=1_000_000, move_factor=2.0)
        self.assertFalse(a["profitable"])
        out = hunt.format_assessment("deep", a)
        self.assertIn("likely safe", out)


class TestSourceScan(unittest.TestCase):
    def test_flags_unmitigated_spot_read(self):
        src = "function getPrice() public view returns (uint) { (uint r0, uint r1,) = pair.getReserves(); return r1 * 1e18 / r0; }"
        scan = hunt.scan_source(src)
        self.assertIn("getReserves", scan["risky"])
        self.assertFalse(scan["mitigations"])
        self.assertTrue(scan["suspicious"])  # risky read, no Chainlink/TWAP

    def test_not_suspicious_when_chainlink_present(self):
        src = "getReserves(); ... latestRoundData(); // uses Chainlink as the reference"
        scan = hunt.scan_source(src)
        self.assertIn("getReserves", scan["risky"])
        self.assertIn("latestRoundData", scan["mitigations"])
        self.assertFalse(scan["suspicious"])

    def test_clean_source_has_no_risky_reads(self):
        src = "function transfer(address to, uint256 amt) external returns (bool) {}"
        scan = hunt.scan_source(src)
        self.assertEqual(scan["risky"], {})
        self.assertIn("no obvious spot-price reads", hunt.format_scan("x", scan))

    def test_etherscan_chain_map(self):
        # the multichain helper knows the major EVM chain ids
        self.assertEqual(hunt.ETHERSCAN_CHAINS["ethereum"], 1)
        self.assertEqual(hunt.ETHERSCAN_CHAINS["bsc"], 56)
        self.assertEqual(hunt.ETHERSCAN_CHAINS["base"], 8453)


if __name__ == "__main__":
    unittest.main()
