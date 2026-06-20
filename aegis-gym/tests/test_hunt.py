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


if __name__ == "__main__":
    unittest.main()
