"""Registry-integrity and report-rendering tests (no forge required)."""
import unittest

from aegis import registry, report


class TestRegistry(unittest.TestCase):
    def test_scenarios_are_well_formed(self):
        for sc in registry.all_scenarios():
            self.assertTrue(sc.match_test and sc.json_file)
            self.assertTrue(sc.attacker_grid, f"{sc.key} has no attacker grid")
            self.assertGreater(sc.benign_total, 0)
            self.assertTrue(sc.families, f"{sc.key} has no defense families")
            for fam in sc.families.values():
                self.assertTrue(fam, "empty family")
                for cfg in fam:
                    self.assertTrue(cfg.label and cfg.family)

    def test_every_scenario_has_a_structural_family(self):
        # the central thesis needs a structural baseline to compare against.
        for sc in registry.all_scenarios():
            has_structural = any(c.structural for fam in sc.families.values() for c in fam)
            self.assertTrue(has_structural, f"{sc.key} lacks a structural defense")

    def test_scenario_ids_and_keys_unique(self):
        ids = [sc.id for sc in registry.all_scenarios()]
        keys = [sc.key for sc in registry.all_scenarios()]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(len(keys), len(set(keys)))


class TestReportRendering(unittest.TestCase):
    def _fake_report(self):
        return {
            "generated_utc": "2026-01-01T00:00:00Z",
            "scenarios": {
                "demo": {
                    "id": "01",
                    "title": "Demo",
                    "summary": "a summary",
                    "attacker_knob": "ATK",
                    "attacker_grid": [1, 2],
                    "benign_total": 2,
                    "leaderboard": [
                        {
                            "scenario": "demo", "family": "struct", "label": "S",
                            "structural": True, "worst_case_saved": 1.0,
                            "worst_case_reward": 1.0, "mean_saved": 1.0, "fp": 0,
                            "benign_total": 2,
                        }
                    ],
                    "generalization": {
                        "train": [2], "test": [1],
                        "rows": [
                            {
                                "scenario": "demo", "family": "struct",
                                "trained_label": "S", "structural": True,
                                "train": 1.0, "test": 1.0, "gap": 0.0,
                            }
                        ],
                    },
                }
            },
        }

    def test_markdown_contains_key_sections(self):
        md = report.render_markdown(self._fake_report())
        self.assertIn("# Aegis leaderboard", md)
        self.assertIn("Scenario 01 — Demo", md)
        self.assertIn("Generalization to unseen attackers", md)
        self.assertIn("generalizes", md)


if __name__ == "__main__":
    unittest.main()
