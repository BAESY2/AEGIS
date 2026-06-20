"""Tests for the combinatorial space quantifier (pure arithmetic, no forge)."""
import unittest

from aegis import space
from aegis.space import ScenarioSpace


class TestSpace(unittest.TestCase):
    def test_composition_identity(self):
        # non-empty AND-stacks over primitives with cardinalities {2,3}:
        # prod(c+1)-1 = 3*4-1 = 11 stacks (parameter-expanded)
        s = ScenarioSpace(key="x", primitives={"a": 2, "b": 3}, attacker_card=1, modes=1)
        self.assertEqual(s.singleton_defenses(), 5)  # 2 + 3
        self.assertEqual(s.composite_defenses(), 11)  # 3*4 - 1

    def test_modes_multiply_multi_stacks(self):
        s1 = ScenarioSpace(key="x", primitives={"a": 2, "b": 3}, attacker_card=1, modes=1)
        s2 = ScenarioSpace(key="x", primitives={"a": 2, "b": 3}, attacker_card=1, modes=2)
        # multi-member stacks (11 - 5 = 6) get the extra mode; singletons (5) don't
        self.assertEqual(s2.composite_defenses(), 5 + 6 * 2)

    def test_report_is_large(self):
        rep = space.report(dataset_size=1410)
        self.assertGreater(rep["total_matchups"], 1e9)
        self.assertGreater(rep["log10"], 9)
        self.assertEqual(len(rep["rows"]), len(space.SPACES))
        self.assertLess(rep["coverage_fraction"], 1e-5)


if __name__ == "__main__":
    unittest.main()
