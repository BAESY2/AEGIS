"""Test cross-class transfer logic on synthetic multi-class data (no forge)."""
import unittest

from aegis import sweep, transfer


def _synthetic():
    recs = []
    for i in range(80):
        atk = (i % 6) + 2
        # reentrancy: held iff small attacker; oracle: OPPOSITE rule -> class-specific
        recs.append({"scenario": "reentrancy", "family": "rate-based", "structural": False,
                     "params": {"AEGIS_DEF": "windowed", "AEGIS_WINDOW": (i % 12) + 1},
                     "attacker": atk, "reward": 1.0 if atk <= 4 else -0.5})
        recs.append({"scenario": "oracle", "family": "fixed-anchor", "structural": False,
                     "params": {"AEGIS_GUARD": "fixed", "AEGIS_DEVBPS": 100 * ((i % 6) + 1)},
                     "attacker": atk, "reward": 1.0 if atk >= 5 else -0.5})
    return recs


class TestTransfer(unittest.TestCase):
    def setUp(self):
        self._orig = sweep.read
        sweep.read = _synthetic

    def tearDown(self):
        sweep.read = self._orig

    def test_class_specific_rules_dont_transfer(self):
        rep = transfer.run(seed=0)
        rows = {r["held_out"]: r for r in rep["rows"]}
        self.assertIn("reentrancy", rows)
        self.assertIn("oracle", rows)
        for r in rep["rows"]:
            # within-class should learn its own rule well
            self.assertGreater(r["within_class_acc"], 0.8)
            # opposite per-class rules => positive transfer gap (poor cross-class)
            self.assertGreater(r["transfer_gap"], 0.1)


if __name__ == "__main__":
    unittest.main()
