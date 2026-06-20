"""Test the Pareto frontier computation on synthetic data (no forge)."""
import unittest

from aegis import pareto, sweep


def _synthetic():
    recs = []
    # scenario 'dom': D1 dominates (saved 1.0, fp 0); D2 worse on both.
    for atk in (1, 2):
        recs.append({"scenario": "dom", "params": {"AEGIS_DEF": "D1"}, "attacker": atk,
                     "saved": 1.0, "fp": 0})
        recs.append({"scenario": "dom", "params": {"AEGIS_DEF": "D2"}, "attacker": atk,
                     "saved": 0.5, "fp": 1})
    # scenario 'trade': A (1.0 saved, fp 2) vs B (0.5 saved, fp 0) — non-dominated.
    for atk in (1, 2):
        recs.append({"scenario": "trade", "params": {"AEGIS_DEF": "A"}, "attacker": atk,
                     "saved": 1.0, "fp": 2})
        recs.append({"scenario": "trade", "params": {"AEGIS_DEF": "B"}, "attacker": atk,
                     "saved": 0.5, "fp": 0})
    return recs


class TestPareto(unittest.TestCase):
    def setUp(self):
        self._orig = sweep.read
        sweep.read = _synthetic

    def tearDown(self):
        sweep.read = self._orig

    def test_dominant_collapses_to_one_point(self):
        self.assertEqual(len(pareto.run("dom")["frontier"]), 1)

    def test_tradeoff_has_two_points(self):
        front = pareto.run("trade")["frontier"]
        self.assertEqual(len(front), 2)
        savds = sorted(p["mean_saved"] for p in front)
        self.assertEqual(savds, [0.5, 1.0])


if __name__ == "__main__":
    unittest.main()
