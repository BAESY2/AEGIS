"""Tests for the active-learning acquisition curves (synthetic, no forge/corpus)."""
import unittest

from aegis import active


def _records(n=120):
    recs = []
    for i in range(n):
        atk = (i % 6) + 2  # 2..7
        recs.append(
            {
                "scenario": "reentrancy",
                "structural": (i % 5 == 0),
                "params": {"AEGIS_DEF": "windowed", "AEGIS_WINDOW": (i % 12) + 1, "AEGIS_CAP": (i % 8) + 1},
                "attacker": atk,
                # separable label: smaller attackers are "held" (positive reward)
                "reward": 1.0 if atk <= 4 else -0.5,
            }
        )
    return recs


class TestActiveCurves(unittest.TestCase):
    def test_curve_shapes_and_learning(self):
        recs = _records(120)
        test_idx = set(range(0, 120, 4))  # 30 held out
        for strat in ("random", "active", "committee"):
            curve = active._al_curve(strat, recs, test_idx, seed=0, rounds=4, batch=10, seed_size=10)
            self.assertEqual(len(curve), 4)
            # labels grow each round
            labels = [n for n, _ in curve]
            self.assertEqual(labels, sorted(labels))
            # accuracies are valid probabilities
            for _, acc in curve:
                self.assertGreaterEqual(acc, 0.0)
                self.assertLessEqual(acc, 1.0)
            # on a separable problem the model should learn something
            self.assertGreater(curve[-1][1], 0.6)


if __name__ == "__main__":
    unittest.main()
