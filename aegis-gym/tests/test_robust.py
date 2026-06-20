"""Test the minimax / regret computation on a synthetic payoff matrix (no forge)."""
import unittest

from aegis import robust, sweep


def _synthetic():
    # Defense A (amount cap=3): great at low stealth, bad at high.
    # Defense B (newdest): flat and robust.
    rewards = {
        ("amount", 3): {0: 1.0, 50: 0.0, 100: -0.5},
        ("newdest", None): {0: 0.5, 50: 0.5, 100: 0.5},
    }
    recs = []
    for (kind, cap), row in rewards.items():
        for s, rew in row.items():
            params = {"AEGIS_DEF": kind}
            if cap is not None:
                params["AEGIS_CAP"] = cap
            recs.append({"scenario": "behavioral", "family": kind, "structural": False,
                         "params": params, "attacker": s, "reward": rew, "fp": 0, "saved": max(0.0, rew)})
    return recs


class TestRobust(unittest.TestCase):
    def setUp(self):
        self._orig = sweep.read
        sweep.read = _synthetic

    def tearDown(self):
        sweep.read = self._orig

    def test_minimax_and_regret(self):
        r = robust.run("behavioral")
        # B (newdest) is the robust choice: worst case 0.5 > A's -0.5
        self.assertIn("newdest", r["robust_defense"])
        self.assertAlmostEqual(r["robust_worstcase"], 0.5)
        # oracle mean = (1.0 + 0.5 + 0.5)/3 = 0.667; regret = 0.667 - 0.5
        self.assertAlmostEqual(r["oracle_mean"], 0.667, places=2)
        self.assertGreater(r["regret_of_not_knowing_attacker"], 0.1)
        # crossover: best response switches from A (low stealth) to B (high)
        self.assertEqual(len(r["crossover"]), 2)


if __name__ == "__main__":
    unittest.main()
