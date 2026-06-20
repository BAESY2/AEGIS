"""Tests for the AMM defense co-evolution search (pure-Python, no forge).

These mirror the Solidity ground truth: PriceImpactGuard is evaded by splitting
(test/SplitTradeEvasion.t.sol), and CumulativeImpactGuard bounds the drain.
"""
import unittest

from aegis import dex
from aegis.dex import Pool, PerTradeCap, WindowedCumulativeCap


class TestDexMechanics(unittest.TestCase):
    def test_impact_matches_constant_product(self):
        p = Pool(1_000_000.0, 1_000_000.0)
        # tiny trade -> near-zero impact; half-pool -> large impact
        self.assertLess(p.impact_bps(1_000.0), 50)
        self.assertGreater(p.impact_bps(500_000.0), 5000)

    def test_execute_conserves_direction(self):
        p = Pool(1_000_000.0, 2_000_000.0)
        out = p.execute(10_000.0)
        self.assertGreater(out, 0)
        self.assertEqual(p.reserve_in, 1_010_000.0)
        self.assertLess(p.reserve_out, 2_000_000.0)


class TestCoevolution(unittest.TestCase):
    def test_attacker_discovers_split_under_per_trade_cap(self):
        make = lambda: Pool(1_000_000.0, 2_000_000_000.0)
        atk = dex.attacker_best_response(make, PerTradeCap(200))
        # the search chooses small repeated chunks and drains most of the pool
        self.assertLess(atk["chunk_frac"], 0.05)
        self.assertGreater(atk["trades"], 10)
        self.assertGreater(atk["drain_bps"], 5000)  # >50% drained

    def test_windowed_cap_bounds_the_drain(self):
        make = lambda: Pool(1_000_000.0, 2_000_000_000.0)
        guard = WindowedCumulativeCap(500)
        atk = dex.attacker_best_response(make, guard)
        # however the attacker slices it, drain is bounded near the window cap
        self.assertLess(atk["drain_bps"], 700)

    def test_benign_trader_admitted_by_chosen_cap(self):
        make = lambda: Pool(1_000_000.0, 2_000_000_000.0)
        guard = dex.defender_best_response(make, benign_bps=500)
        self.assertTrue(dex.benign_passes(make, guard, 500))

    def test_full_round_cuts_drain_by_an_order_of_magnitude(self):
        r = dex.coevolve()
        self.assertGreater(r["round0"]["drain_bps"], 5000)
        self.assertLess(r["round1"]["drain_bps"], 700)
        self.assertTrue(r["round1"]["benign_admitted"])
        # the equilibrium drain is far smaller than the evaded per-trade cap
        self.assertLess(r["round1"]["drain_bps"], r["round0"]["drain_bps"] / 5)


if __name__ == "__main__":
    unittest.main()
