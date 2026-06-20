"""Tests for the pure-Python MLP — including a nonlinear (XOR) problem the
logistic-regression baseline provably cannot fit."""
import unittest

from aegis import classify, mlp


def _xor(n=400):
    X, y = [], []
    pts = [((0.0, 0.0), 0), ((1.0, 1.0), 0), ((0.0, 1.0), 1), ((1.0, 0.0), 1)]
    for i in range(n):
        (a, b), lab = pts[i % 4]
        X.append([a, b])
        y.append(lab)
    return X, y


class TestMLP(unittest.TestCase):
    def test_predict_proba_in_range(self):
        m = mlp.train([[0.0, 0.0], [1.0, 1.0]], [0, 1], epochs=50, seed=0)
        p = m.predict_proba([0.5, 0.5])
        self.assertGreaterEqual(p, 0.0)
        self.assertLessEqual(p, 1.0)

    def test_learns_xor_that_logreg_cannot(self):
        X, y = _xor()
        m = mlp.train(X, y, hidden=8, epochs=2000, lr=0.5, seed=1)
        acc = classify.evaluate(m, X, y)["accuracy"]
        self.assertGreater(acc, 0.95, f"MLP should fit XOR; got {acc}")

        # the linear model cannot separate XOR (sanity: it stays near chance)
        lin = classify.train(X, y, epochs=400, seed=0)
        lin_acc = classify.evaluate(lin, X, y)["accuracy"]
        self.assertLess(lin_acc, 0.8, f"logreg cannot fit XOR; got {lin_acc}")


if __name__ == "__main__":
    unittest.main()
