"""A learned defense-outcome classifier — the data moat's payoff.

Trains a logistic-regression model on the EVM-verified trajectory dataset to
predict whether a defense will *hold* (reward > 0) from its features alone —
scenario, whether it is structural, its parameters, and the attacker strength.
No numpy: standardization and gradient descent are written out explicitly, so
the only runtime requirement stays `python3`.

The point is the loop: the environment produces label-free, execution-grounded
data; that data trains a model that predicts defense quality without running the
EVM — and it independently rediscovers the project's central law (structural
defenses hold). The more matchups the dataset accumulates, the better this model
gets: the compounding data asset, made tangible.
"""
from __future__ import annotations

import math
import random
from dataclasses import dataclass

from . import sweep

SCENARIOS = ["reentrancy", "oracle", "access", "governance"]
_ATTACKER_SCALE = {"reentrancy": 11.0, "access": 11.0, "oracle": 200.0, "governance": 5000.0}
FEATURE_NAMES = [f"is_{s}" for s in SCENARIOS] + ["structural", "param_a", "param_b", "attacker"]


def featurize(rec: dict) -> list[float]:
    sc = rec["scenario"]
    onehot = [1.0 if sc == s else 0.0 for s in SCENARIOS]
    structural = 1.0 if rec.get("structural") else 0.0
    p = rec.get("params", {})
    a = b = 0.0
    if "AEGIS_WINDOW" in p:
        a = float(p["AEGIS_WINDOW"]) / 12.0
    if "AEGIS_DEVBPS" in p:
        a = float(p["AEGIS_DEVBPS"]) / 2000.0
    if "AEGIS_CAP" in p:
        cap = float(p["AEGIS_CAP"])
        b = cap / (6000.0 if sc == "governance" else 12.0)
    atk = float(rec["attacker"]) / _ATTACKER_SCALE.get(sc, 1.0)
    return onehot + [structural, a, b, atk]


def label(rec: dict) -> int:
    return 1 if rec["reward"] > 0 else 0


@dataclass
class Model:
    weights: list[float]
    bias: float
    mean: list[float]
    std: list[float]

    def _standardize(self, x: list[float]) -> list[float]:
        return [(xi - m) / s for xi, m, s in zip(x, self.mean, self.std)]

    def predict_proba(self, x: list[float]) -> float:
        z = self.bias + sum(w * xi for w, xi in zip(self.weights, self._standardize(x)))
        return 1.0 / (1.0 + math.exp(-max(-30.0, min(30.0, z))))

    def predict(self, x: list[float]) -> int:
        return 1 if self.predict_proba(x) >= 0.5 else 0


def _standardization(X: list[list[float]]) -> tuple[list[float], list[float]]:
    n, d = len(X), len(X[0])
    mean = [sum(row[j] for row in X) / n for j in range(d)]
    std = []
    for j in range(d):
        var = sum((row[j] - mean[j]) ** 2 for row in X) / n
        std.append(math.sqrt(var) or 1.0)
    return mean, std


def train(
    X: list[list[float]], y: list[int], epochs: int = 300, lr: float = 0.3, l2: float = 1e-3, seed: int = 0
) -> Model:
    mean, std = _standardization(X)
    Xs = [[(xi - m) / s for xi, m, s in zip(row, mean, std)] for row in X]
    d = len(Xs[0])
    w = [0.0] * d
    bias = 0.0
    rng = random.Random(seed)
    idx = list(range(len(Xs)))
    for _ in range(epochs):
        rng.shuffle(idx)
        for i in idx:
            xi, yi = Xs[i], y[i]
            z = bias + sum(wj * xj for wj, xj in zip(w, xi))
            p = 1.0 / (1.0 + math.exp(-max(-30.0, min(30.0, z))))
            err = p - yi
            for j in range(d):
                w[j] -= lr * (err * xi[j] + l2 * w[j])
            bias -= lr * err
    return Model(weights=w, bias=bias, mean=mean, std=std)


def evaluate(model: Model, X: list[list[float]], y: list[int]) -> dict:
    tp = tn = fp = fn = 0
    for xi, yi in zip(X, y):
        pred = model.predict(xi)
        if pred == 1 and yi == 1:
            tp += 1
        elif pred == 0 and yi == 0:
            tn += 1
        elif pred == 1 and yi == 0:
            fp += 1
        else:
            fn += 1
    n = max(1, tp + tn + fp + fn)
    acc = (tp + tn) / n
    prec = tp / (tp + fp) if (tp + fp) else 0.0
    rec = tp / (tp + fn) if (tp + fn) else 0.0
    return {"accuracy": acc, "precision": prec, "recall": rec, "tp": tp, "tn": tn, "fp": fp, "fn": fn}


def run(test_frac: float = 0.25, seed: int = 0) -> dict:
    """Load the dataset, train/test split, fit, and report."""
    records = sweep.read()
    if len(records) < 20:
        raise RuntimeError(
            f"dataset too small ({len(records)} records). "
            "Generate it first: python3 -m aegis dataset --budget 200"
        )
    rng = random.Random(seed)
    rng.shuffle(records)
    cut = int(len(records) * (1 - test_frac))
    train_recs, test_recs = records[:cut], records[cut:]

    Xtr = [featurize(r) for r in train_recs]
    ytr = [label(r) for r in train_recs]
    Xte = [featurize(r) for r in test_recs]
    yte = [label(r) for r in test_recs]

    model = train(Xtr, ytr, seed=seed)
    train_metrics = evaluate(model, Xtr, ytr)
    test_metrics = evaluate(model, Xte, yte)
    weights = sorted(
        zip(FEATURE_NAMES, model.weights), key=lambda kv: abs(kv[1]), reverse=True
    )
    base_rate = sum(yte) / len(yte) if yte else 0.0

    # per-scenario test accuracy — shows the model works across every class
    per_scenario: dict[str, dict] = {}
    for rec in test_recs:
        m = evaluate(model, [featurize(rec)], [label(rec)])
        s = per_scenario.setdefault(rec["scenario"], {"n": 0, "correct": 0})
        s["n"] += 1
        s["correct"] += m["tp"] + m["tn"]
    for s in per_scenario.values():
        s["accuracy"] = s["correct"] / s["n"] if s["n"] else 0.0

    return {
        "n_total": len(records),
        "n_train": len(train_recs),
        "n_test": len(test_recs),
        "test_base_rate": base_rate,
        "train": train_metrics,
        "test": test_metrics,
        "per_scenario": per_scenario,
        "weights": weights,
    }
