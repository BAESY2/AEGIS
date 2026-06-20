"""A Gymnasium-style RL environment over the verifiable Foundry scorer.

The environment is deliberately dependency-free: it follows the Gymnasium
``reset()`` / ``step(action)`` contract and exposes ``action_space`` /
``observation_space`` as light Box descriptors, but does not import gymnasium.
If gymnasium *is* installed you can trivially wrap this; we keep the core
zero-dependency so `forge test` + `python3` is the only requirement.

The flagship environment, ``RobustRateLimitEnv``, asks an agent to choose a
*continuous* circuit-breaker configuration (window, cap). Each step evaluates
that configuration against the entire attacker grid on the EVM and returns the
**worst-case** reward — so the agent is optimizing exactly the robustness
objective the co-evolution study cares about: be precise against your worst
attacker, not your average one. A policy-gradient agent given only this signal
rediscovers the robust windowed breaker, with no hand-set answer.
"""
from __future__ import annotations

from dataclasses import dataclass

from . import registry
from .analysis import ScoreCache
from .registry import DefenseConfig, Scenario


@dataclass(frozen=True)
class Box:
    """Minimal continuous space descriptor (low/high per dimension)."""

    low: tuple[float, ...]
    high: tuple[float, ...]

    @property
    def shape(self) -> tuple[int, ...]:
        return (len(self.low),)

    def clip(self, action) -> tuple[float, ...]:
        return tuple(min(hi, max(lo, a)) for a, lo, hi in zip(action, self.low, self.high))


class RobustRateLimitEnv:
    """Continuous (window, cap) -> worst-case reward over the attacker grid.

    Action  : (window, cap), each a real number; rounded to the integer grid the
              on-chain WindowedRateLimitDefense accepts.
    Reward  : min over the scenario's attacker grid of (funds_saved - fp_rate),
              i.e. the worst-case verifiable reward. A single scalar in [-1, 1].
    Episode : one step (a contextual-bandit / black-box optimization setting);
              ``reset`` returns a constant observation since the agent picks a
              global defense configuration rather than reacting to a state.
    """

    def __init__(self, scenario: str = "reentrancy", cache: ScoreCache | None = None):
        self.scenario: Scenario = registry.get(scenario)
        self.cache = cache or ScoreCache()
        self.window_bounds = (1, 12)
        self.cap_bounds = (1, 12)
        self.action_space = Box(
            low=(self.window_bounds[0], self.cap_bounds[0]),
            high=(self.window_bounds[1], self.cap_bounds[1]),
        )
        self.observation_space = Box(low=(0.0,), high=(1.0,))

    # -- Gymnasium-style API ------------------------------------------------ #
    def reset(self, *, seed: int | None = None):
        return (0.0,), {}

    def step(self, action):
        window, cap = self._discretize(action)
        cfg = DefenseConfig(
            family="rate-based",
            label=f"WindowedRateLimit(w={window}, cap={cap})",
            env={"AEGIS_DEF": "windowed", "AEGIS_WINDOW": window, "AEGIS_CAP": cap},
        )
        rewards = [self.cache.score(self.scenario, cfg, a).reward for a in self.scenario.attacker_grid]
        worst = min(rewards)
        info = {
            "window": window,
            "cap": cap,
            "worst_case_reward": worst,
            "mean_reward": sum(rewards) / len(rewards),
            "per_attacker": dict(zip(self.scenario.attacker_grid, rewards)),
        }
        # single-step episode: terminated=True, truncated=False
        return (0.0,), worst, True, False, info

    def _discretize(self, action) -> tuple[int, int]:
        w, c = self.action_space.clip(action)
        return int(round(w)), int(round(c))
