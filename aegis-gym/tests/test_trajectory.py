"""Tests for the trajectory ledger (uses a temp file, not the real ledger)."""
import tempfile
import unittest
from pathlib import Path

from aegis import trajectory
from aegis.registry import DefenseConfig, MatchResult


class TestTrajectoryLedger(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self._orig = trajectory.LEDGER
        trajectory.LEDGER = Path(self._tmp.name) / "trajectories.jsonl"

    def tearDown(self):
        trajectory.LEDGER = self._orig
        self._tmp.cleanup()

    def _log(self, family, label, structural, attacker, reward):
        cfg = DefenseConfig(family, label, {}, structural=structural)
        res = MatchResult(saved=1.0 if reward > 0 else 0.0, fp=0, benign_total=2, reward=reward)
        trajectory.log("demo", cfg, attacker, res)

    def test_log_and_summary(self):
        self._log("struct", "S", True, 1, 1.0)
        self._log("struct", "S", True, 2, 1.0)
        self._log("thresh", "T", False, 1, 1.0)
        self._log("thresh", "T", False, 2, -0.5)

        records = trajectory.read()
        self.assertEqual(len(records), 4)

        s = trajectory.summary()
        self.assertEqual(s["total_matchups"], 4)
        fams = s["scenarios"]["demo"]["families"]
        self.assertEqual(fams["struct"]["wins"], 2)  # both positive
        self.assertEqual(fams["thresh"]["wins"], 1)  # one positive, one negative
        self.assertTrue(fams["struct"]["structural"])

    def test_disabled_via_env(self):
        import os

        os.environ["AEGIS_NO_TRAJECTORY"] = "1"
        try:
            self._log("struct", "S", True, 1, 1.0)
            self.assertEqual(trajectory.read(), [])
        finally:
            del os.environ["AEGIS_NO_TRAJECTORY"]


if __name__ == "__main__":
    unittest.main()
