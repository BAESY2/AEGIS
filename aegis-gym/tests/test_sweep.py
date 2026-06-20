"""Tests for dataset stats/card rendering (uses a temp corpus, no forge)."""
import json
import tempfile
import unittest
from pathlib import Path

from aegis import sweep


class TestSweepStats(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self._orig_corpus, self._orig_card = sweep.CORPUS, sweep.CARD
        sweep.CORPUS = Path(self._tmp.name) / "trajectories.jsonl"
        sweep.CARD = Path(self._tmp.name) / "DATASET.md"
        rows = [
            {"scenario": "demo", "family": "struct", "structural": True,
             "params": {"AEGIS_DEF": "x"}, "attacker": 1, "saved": 1.0, "fp": 0, "reward": 1.0},
            {"scenario": "demo", "family": "thresh", "structural": False,
             "params": {"AEGIS_CAP": 3}, "attacker": 2, "saved": 0.0, "fp": 1, "reward": -0.5},
            {"scenario": "demo", "family": "thresh", "structural": False,
             "params": {"AEGIS_CAP": 8}, "attacker": 3, "saved": 1.0, "fp": 0, "reward": 1.0},
        ]
        sweep.CORPUS.write_text("\n".join(json.dumps(r) for r in rows) + "\n")

    def tearDown(self):
        sweep.CORPUS, sweep.CARD = self._orig_corpus, self._orig_card
        self._tmp.cleanup()

    def test_stats_counts(self):
        s = sweep.stats()
        self.assertEqual(s["total"], 3)
        self.assertEqual(s["positive_reward"], 2)
        self.assertEqual(s["negative_or_zero_reward"], 1)
        self.assertEqual(s["scenarios"]["demo"]["families"]["thresh"]["n"], 2)

    def test_card_renders(self):
        path = sweep.write_card()
        md = path.read_text()
        self.assertIn("# Aegis trajectory dataset", md)
        self.assertIn("Records:", md)
        self.assertIn("demo", md)


if __name__ == "__main__":
    unittest.main()
