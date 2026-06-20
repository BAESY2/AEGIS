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
        self.assertEqual(len(wild.CONSENSUS_VENUES), 2)


class TestCrossVenue(unittest.TestCase):
    def test_usd_price_and_percentile(self):
        # USDC(6)/WETH(18): ~$1700 per ETH, returned at 1e18 scale (deviation is a ratio)
        usd = wild._usd(1_700_000 * 10**6, 1000 * 10**18)
        self.assertAlmostEqual(usd / 1e18, 1700.0, delta=1.0)
        self.assertEqual(wild._pct([], 50), 0.0)
        self.assertEqual(wild._pct([10, 20, 30], 50), 20)

    def test_cross_venue_report_formats(self):
        rep = {
            "venues": ["uniswap", "sushiswap"],
            "samples": 4,
            "devs": [5.0, 10.0, 60.0, 120.0],
            "over_50bps": 2,
            "over_100bps": 1,
            "over_200bps": 0,
            "persist_50bps": 1,
            "persist_100bps": 0,
            "persist_200bps": 0,
            "chunks_ok": 2,
            "chunks_failed": 0,
        }
        out = wild.format_cross_venue(rep, 100, 200)
        self.assertIn("4 real cross-venue price samples", out)
        self.assertIn("instantaneous flag", out)
        self.assertIn("persistent flag", out)


if __name__ == "__main__":
    unittest.main()
