"""Logic tests for the analysis layer — no forge required (results are stubbed).

These pin the benchmark's selection logic: the leaderboard ranks by worst-case
reward, the train/test split is disjoint and uses the hardest (strong->weak)
protocol, and best-response maximizes worst-case train reward. A stub cache
supplies canned MatchResults so the math is tested in isolation from the EVM.
"""
import unittest

from aegis import analysis
from aegis.registry import DefenseConfig, MatchResult, Scenario


def mr(saved, fp=0, benign=2, reward=None):
    reward = saved - fp / benign if reward is None else reward
    return MatchResult(saved=saved, fp=fp, benign_total=benign, reward=reward)


class FakeCache:
    """A ScoreCache stand-in returning canned results keyed by (label, attacker)."""

    def __init__(self, table):
        self.table = table

    def score(self, scenario, config, attacker):
        return self.table[(config.label, attacker)]


def fake_scenario():
    th_lo = DefenseConfig("th", "TH-lo", {"P": 1})
    th_hi = DefenseConfig("th", "TH-hi", {"P": 9})
    struct = DefenseConfig("struct", "STRUCT", {"S": 1}, structural=True)
    sc = Scenario(
        id="99",
        key="fake",
        title="Fake",
        summary="",
        match_test="t",
        json_file="t.json",
        attacker_knob="ATK",
        attacker_grid=[1, 2, 3, 4],
        benign_total=2,
        families={"th": [th_lo, th_hi], "struct": [struct]},
    )
    # TH-hi: perfect on strong attackers (3,4), useless on weak (1,2) -> overfit.
    # TH-lo: weak everywhere. STRUCT: perfect everywhere -> generalizes.
    table = {}
    for a in [1, 2, 3, 4]:
        table[("STRUCT", a)] = mr(1.0, 0)
        table[("TH-hi", a)] = mr(1.0, 0) if a >= 3 else mr(0.0, 0)
        table[("TH-lo", a)] = mr(0.5 if a == 1 else 0.0, 0)
    return sc, FakeCache(table)


class TestSplit(unittest.TestCase):
    def test_split_is_disjoint_and_complete(self):
        train, test = analysis._split([1, 2, 3, 4, 5, 6])
        self.assertEqual(set(train) & set(test), set())
        self.assertEqual(sorted(train + test), [1, 2, 3, 4, 5, 6])

    def test_trains_on_strong_attackers(self):
        train, test = analysis._split([2, 3, 4, 5, 7, 11])
        self.assertTrue(min(train) >= max(test), "train should be the stronger half")


class TestLeaderboard(unittest.TestCase):
    def test_structural_ranks_first_by_worst_case(self):
        sc, cache = fake_scenario()
        rows = analysis.leaderboard(sc, cache)
        self.assertEqual(rows[0].label, "STRUCT")
        self.assertEqual(rows[0].worst_case_reward, 1.0)
        # TH-hi has worst-case reward 0 (fails on weak attackers)
        th_hi = next(r for r in rows if r.label == "TH-hi")
        self.assertEqual(th_hi.worst_case_reward, 0.0)


class TestGeneralization(unittest.TestCase):
    def test_threshold_overfits_structural_generalizes(self):
        sc, cache = fake_scenario()
        rows, train, test = analysis.generalization(sc, cache)
        by_family = {r.family: r for r in rows}
        self.assertEqual(by_family["th"].trained_label, "TH-hi")  # best on strong train
        self.assertAlmostEqual(by_family["th"].train, 1.0)
        self.assertAlmostEqual(by_family["th"].test, 0.0)
        self.assertAlmostEqual(by_family["th"].gap, 1.0)  # overfits
        self.assertAlmostEqual(by_family["struct"].gap, 0.0)  # generalizes


if __name__ == "__main__":
    unittest.main()
