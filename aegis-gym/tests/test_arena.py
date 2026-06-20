"""Tests for the population (swarm) co-evolution training ground."""
import unittest

from aegis import arena


class TestArena(unittest.TestCase):
    def test_drain_and_benign(self):
        # a wide-open defender lets an attacker drain a lot; a tight windowed cap bounds it
        self.assertGreater(arena._drain((2000.0, 5000.0), 0.01), 0.3)
        self.assertLess(arena._drain((400.0, 500.0), 0.01), 0.07)
        # a defender that admits honest 5%/window traffic
        self.assertTrue(arena._benign_ok((400.0, 500.0)))
        # a defender whose window cap is below the honest floor blocks real users
        self.assertFalse(arena._benign_ok((400.0, 100.0)))

    def test_swarm_curve_improves(self):
        co = arena.coevolve(seed=0)
        curve = [h["worst_drain"] for h in co["history"]]
        # the best defender's worst-case drain at the end is no worse than the start
        self.assertLessEqual(curve[-1], curve[0] + 1e-9)

    def test_swarm_generalizes_better_than_single_threat(self):
        for seed in range(4):
            r = arena.generalization_study(seed=seed)
            # swarm training caps unseen attackers well below single-threat tuning
            self.assertLess(r["league_worst_drain"], 0.15)
            self.assertGreater(r["single_worst_drain"], 0.25)
            self.assertLess(r["league_worst_drain"], r["single_worst_drain"])

    def test_report_mentions_generalization(self):
        out = arena.format_report(arena.generalization_study(seed=0))
        self.assertIn("Swarm training generalizes", out)


if __name__ == "__main__":
    unittest.main()
