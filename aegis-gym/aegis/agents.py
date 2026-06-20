"""Dependency-free RL agents for the Aegis environments.

`GaussianREINFORCE` is a policy-gradient agent over a continuous action: it
maintains a diagonal Gaussian policy N(mu, sigma) over the defense parameters,
samples a configuration, observes the verifiable worst-case reward, and nudges
mu up the score-function gradient

    mu <- mu + lr * (R - baseline) * (a - mu) / sigma^2

with a moving-average baseline for variance reduction and an annealed sigma to
shift from exploration to exploitation. No numpy: actions are short tuples and
the math is explicit, so the only runtime requirement stays `forge` + `python3`.

The point is not the optimizer's sophistication; it is that the reward is
real, execution-grounded, and label-free, so gradient learning drives the
agent to the *robust* defense the co-evolution study found by grid search.
"""
from __future__ import annotations

import math
import random
from dataclasses import dataclass, field


@dataclass
class TrainStep:
    episode: int
    action: tuple
    reward: float
    best_action: tuple
    best_reward: float
    sigma: float


@dataclass
class GaussianREINFORCE:
    low: tuple[float, ...]
    high: tuple[float, ...]
    lr: float = 0.4
    sigma0: float = 3.0
    sigma_min: float = 0.4
    seed: int = 0
    mu: list[float] = field(default_factory=list)
    _baseline: float = 0.0
    _rng: random.Random = field(default=None, repr=False)

    def __post_init__(self):
        self._rng = random.Random(self.seed)
        if not self.mu:
            # start at the centre of the action box
            self.mu = [(lo + hi) / 2.0 for lo, hi in zip(self.low, self.high)]

    def _sigma(self, episode: int, episodes: int) -> float:
        frac = episode / max(1, episodes)
        return self.sigma_min + (self.sigma0 - self.sigma_min) * (1.0 - frac)

    def sample(self, sigma: float) -> tuple[float, ...]:
        return tuple(
            min(hi, max(lo, self._rng.gauss(m, sigma)))
            for m, lo, hi in zip(self.mu, self.low, self.high)
        )

    def update(self, action, reward: float, sigma: float, alpha: float = 0.2):
        advantage = reward - self._baseline
        self._baseline += alpha * advantage  # moving-average baseline
        for i, a in enumerate(action):
            grad = (a - self.mu[i]) / (sigma * sigma)
            self.mu[i] += self.lr * advantage * grad
            self.mu[i] = min(self.high[i], max(self.low[i], self.mu[i]))

    def learn(self, env, episodes: int = 30, verbose: bool = True) -> list[TrainStep]:
        history: list[TrainStep] = []
        best_action, best_reward = None, -math.inf
        if verbose:
            print(f"{'ep':>3} {'window':>7} {'cap':>5} {'reward':>8} {'sigma':>6}   best")
            print("-" * 52)
        for ep in range(1, episodes + 1):
            sigma = self._sigma(ep, episodes)
            action = self.sample(sigma)
            _, reward, _, _, info = env.step(action)
            self.update(action, reward, sigma)
            disc = (info["window"], info["cap"])
            if reward > best_reward:
                best_action, best_reward = disc, reward
            history.append(TrainStep(ep, disc, reward, best_action, best_reward, round(sigma, 2)))
            if verbose:
                print(
                    f"{ep:>3} {disc[0]:>7} {disc[1]:>5} {reward:>8.2f} {sigma:>6.2f}   "
                    f"{best_action} (r={best_reward:.2f})"
                )
        return history

    def greedy_action(self) -> tuple[int, ...]:
        return tuple(int(round(m)) for m in self.mu)
