"""Tests for the pure-Python logistic-regression classifier (no forge, no data file)."""
import unittest

from aegis import classify


class TestClassifier(unittest.TestCase):
    def test_learns_a_separable_problem(self):
        # label = 1 iff first feature is large; trivially separable
        X, y = [], []
        for i in range(200):
            v = (i % 10) / 10.0
            X.append([v, (i * 7 % 5) / 5.0])
            y.append(1 if v > 0.5 else 0)
        model = classify.train(X, y, epochs=200, seed=0)
        metrics = classify.evaluate(model, X, y)
        self.assertGreater(metrics["accuracy"], 0.9)

    def test_featurize_and_label_shapes(self):
        rec = {
            "scenario": "reentrancy", "structural": False,
            "params": {"AEGIS_DEF": "windowed", "AEGIS_WINDOW": 8, "AEGIS_CAP": 3},
            "attacker": 2, "saved": 0.7, "fp": 1, "reward": 0.45,
        }
        feats = classify.featurize(rec)
        self.assertEqual(len(feats), len(classify.FEATURE_NAMES))
        self.assertEqual(classify.label(rec), 1)
        self.assertEqual(classify.label({**rec, "reward": -0.5}), 0)

    def test_predict_proba_in_range(self):
        model = classify.train([[0.0, 0.0], [1.0, 1.0]], [0, 1], epochs=50, seed=0)
        p = model.predict_proba([0.5, 0.5])
        self.assertGreaterEqual(p, 0.0)
        self.assertLessEqual(p, 1.0)


if __name__ == "__main__":
    unittest.main()
