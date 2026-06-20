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

    def test_real_data_training_separates_cleanly(self):
        # trained on the committed REAL mainnet swap distribution + real attacks
        r = arena.real_data_study()
        self.assertGreater(r["n_benign"], 100)          # hundreds of real swaps
        self.assertEqual(r["false_positive_rate"], 0.0)  # no real swap is blocked
        self.assertEqual(r["attack_recall"], 1.0)        # every real attack is caught
        self.assertGreater(r["margin_x"], 5)             # wide real separation
        self.assertIn("REAL mainnet data", arena.format_real(r))

    def test_adaptive_policy_beats_fixed_cap(self):
        for seed in range(3):
            r = arena.adaptive_study(seed=seed)
            # the context-adaptive policy has lower mean drain than the best fixed cap
            self.assertLess(r["adaptive_mean_drain"], r["fixed_mean_drain"])
            # it learned the rule "cap ~ honest demand": slope near 1, small intercept
            self.assertGreater(r["genome"][1], 0.8)
            self.assertLess(r["genome"][1], 1.3)
            # on the quietest pool it is far tighter than the fixed cap
            b, aw, ad, fd = r["per_pool"][0]
            self.assertLess(ad, fd)


if __name__ == "__main__":
    unittest.main()
