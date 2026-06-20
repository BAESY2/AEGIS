"""Offline tests for the wild-test impact/stats logic (no network).

The live scan needs an RPC; here we feed synthetic Sync sequences through the
same WildStats accounting to lock down the math and the false-positive tally.
"""
import unittest

from aegis import wild
from aegis.wild import WildStats


def _scan_syncs(syncs):
    """Mirror scan_pool's inner loop on an in-memory list of (r0, r1) snapshots."""
    st = WildStats(pool="synthetic")
    prev = None
    for (r0, r1) in syncs:
        if r0 <= 0 or r1 <= 0:
            prev = (r0, r1)
            continue
        if prev is not None and prev[0] > 0 and prev[1] > 0:
            before = wild._mid(*prev)
            after = wild._mid(r0, r1)
            if before > 0 and after > 0:
                imp = abs(1.0 - after / before) * 10000.0
                st.swaps += 1
                st.impacts.append(imp)
                st.max_impact_bps = max(st.max_impact_bps, imp)
                if imp > 200:
                    st.blocked_2pct += 1
                if imp > 500:
                    st.blocked_5pct += 1
                if imp > 1000:
                    st.blocked_10pct += 1
        prev = (r0, r1)
    return st


class TestWildStats(unittest.TestCase):
    def test_calm_market_no_false_positives(self):
        # tiny price drifts -> nothing near the 2% cap
        syncs = [(1_000_000, 1_000_000), (1_000_500, 999_500), (1_001_000, 999_000)]
        st = _scan_syncs(syncs)
        self.assertEqual(st.swaps, 2)
        self.assertEqual(st.blocked_2pct, 0)
        self.assertLess(st.max_impact_bps, 50)
        self.assertEqual(st.fp_rate(200), 0.0)

    def test_large_move_is_flagged(self):
        # a ~50% mid-price move shows up above every threshold
        syncs = [(1_000_000, 1_000_000), (2_000_000, 1_000_000)]
        st = _scan_syncs(syncs)
        self.assertEqual(st.swaps, 1)
        self.assertEqual(st.blocked_2pct, 1)
        self.assertEqual(st.blocked_5pct, 1)
        self.assertEqual(st.blocked_10pct, 1)
        self.assertGreater(st.max_impact_bps, 4000)

    def test_fp_rate_fraction(self):
        # 1 big move out of 4 -> 25% above a 2% cap
        syncs = [
            (1_000_000, 1_000_000),
            (1_000_100, 999_900),  # tiny
            (1_000_200, 999_800),  # tiny
            (1_500_000, 999_800),  # big
        ]
        st = _scan_syncs(syncs)
        self.assertEqual(st.swaps, 3)
        self.assertEqual(st.blocked_2pct, 1)
        self.assertAlmostEqual(st.fp_rate(200), 1 / 3, places=6)

    def test_sync_decoding_constants(self):
        # the Sync topic is the well-known Uniswap V2 event signature hash
        self.assertEqual(len(wild.SYNC_TOPIC), 66)
        self.assertTrue(wild.SYNC_TOPIC.startswith("0x1c411e9a"))
        self.assertEqual(len(wild.TOP_POOLS), 4)


if __name__ == "__main__":
    unittest.main()
