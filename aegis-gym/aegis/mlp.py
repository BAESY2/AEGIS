"""A tiny pure-Python MLP classifier (one hidden layer, no numpy).

Drop-in for the logistic-regression model in `classify` (same `predict_proba` /
`predict` interface), so the active-learning experiment can ask whether a more
expressive, nonlinear model changes the picture — the honest hypothesis being
that active learning helps more when the model has a nonlinear boundary to fit.

Kept deliberately small (1 hidden layer, tanh) so it trains in a fraction of a
second on a few hundred examples and the only runtime dependency stays python3.
"""
from __future__ import annotations

import math
import random
from dataclasses import dataclass

from .classify import _standardization


def _tanh(x: float) -> float:
    if x > 20:
        return 1.0
    if x < -20:
        return -1.0
    return math.tanh(x)


def _sigmoid(x: float) -> float:
    return 1.0 / (1.0 + math.exp(-max(-30.0, min(30.0, x))))


@dataclass
class MLP:
    W1: list[list[float]]
    b1: list[float]
    W2: list[float]
    b2: float
    mean: list[float]
    std: list[float]

    def _std(self, x):
        return [(xi - m) / s for xi, m, s in zip(x, self.mean, self.std)]

    def predict_proba(self, x) -> float:
        xs = self._std(x)
        a1 = [_tanh(sum(w * xj for w, xj in zip(self.W1[j], xs)) + self.b1[j]) for j in range(len(self.b1))]
        z2 = sum(self.W2[j] * a1[j] for j in range(len(a1))) + self.b2
        return _sigmoid(z2)

    def predict(self, x) -> int:
        return 1 if self.predict_proba(x) >= 0.5 else 0


def train(X, y, hidden: int = 8, epochs: int = 200, lr: float = 0.1, l2: float = 1e-4, seed: int = 0) -> MLP:
    mean, std = _standardization(X)
    Xs = [[(xi - m) / s for xi, m, s in zip(row, mean, std)] for row in X]
    d = len(Xs[0])
    rng = random.Random(seed)

    def rnd():
        return (rng.random() - 0.5) * 0.5

    W1 = [[rnd() for _ in range(d)] for _ in range(hidden)]
    b1 = [0.0] * hidden
    W2 = [rnd() for _ in range(hidden)]
    b2 = 0.0

    idx = list(range(len(Xs)))
    for _ in range(epochs):
        rng.shuffle(idx)
        for i in idx:
            xs, yi = Xs[i], y[i]
            # forward
            z1 = [sum(W1[j][k] * xs[k] for k in range(d)) + b1[j] for j in range(hidden)]
            a1 = [_tanh(z) for z in z1]
            z2 = sum(W2[j] * a1[j] for j in range(hidden)) + b2
            p = _sigmoid(z2)
            # backward
            dz2 = p - yi
            for j in range(hidden):
                dz1 = dz2 * W2[j] * (1.0 - a1[j] * a1[j])
                for k in range(d):
                    W1[j][k] -= lr * (dz1 * xs[k] + l2 * W1[j][k])
                b1[j] -= lr * dz1
                W2[j] -= lr * (dz2 * a1[j] + l2 * W2[j])
            b2 -= lr * dz2
    return MLP(W1=W1, b1=b1, W2=W2, b2=b2, mean=mean, std=std)
