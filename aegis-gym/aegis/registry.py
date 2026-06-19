"""The Aegis scenario registry — the single declarative source of truth.

Adding a vulnerability class to the benchmark means appending one ``Scenario``
here (plus its Solidity target/exploit/defenses and an env-driven forge scorer).
Everything else — the leaderboard, the train/test generalization study, the
co-evolution arms race, and the RL environment — is driven off this table, so a
new scenario is picked up everywhere automatically.

Each scenario exposes:
  * an *attacker axis*: a named knob and the grid of values it sweeps;
  * one or more *defense families*: each a set of candidate configurations,
    where every config is a dict of AEGIS_* environment overrides plus a label;
  * the forge test + JSON file that actually scores a single matchup.

A family is "structural" if it enforces an invariant rather than fitting a
numeric threshold; the central Aegis result is that structural families
generalize to unseen attackers while threshold families overfit.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable

from . import foundry


@dataclass(frozen=True)
class MatchResult:
    saved: float          # fraction of funds saved in [0, 1]
    fp: int               # legitimate actions wrongly blocked
    benign_total: int     # size of the benign suite
    reward: float         # execution-derived reward in [-1, 1]


@dataclass(frozen=True)
class DefenseConfig:
    family: str                       # family name (e.g. "rate-based")
    label: str                        # human label for the leaderboard
    env: dict                         # AEGIS_* overrides selecting this config
    structural: bool = False          # enforces an invariant vs. fits a threshold


@dataclass(frozen=True)
class Scenario:
    id: str                           # "01", "02", ...
    key: str                          # short slug, e.g. "reentrancy"
    title: str
    summary: str
    match_test: str                   # forge --match-test target
    json_file: str                    # scoring/<file> the test writes
    attacker_knob: str                # env var carrying the attacker parameter
    attacker_grid: list[int]          # full sweep of attacker strengths
    benign_total: int
    families: dict[str, list[DefenseConfig]]
    static_env: dict = field(default_factory=dict)  # env constant for every run

    def score(self, config: DefenseConfig, attacker: int) -> MatchResult:
        env = {**self.static_env, **config.env, self.attacker_knob: attacker}
        d = foundry.run_test(self.match_test, self.json_file, env)
        saved = d["saved_frac_1e18"] / 1e18
        fp = int(d["fp"])
        reward = d["reward_1e18"] / 1e18
        return MatchResult(saved=saved, fp=fp, benign_total=self.benign_total, reward=reward)


# --------------------------------------------------------------------------- #
# Defense-family builders
# --------------------------------------------------------------------------- #
def _rate_family() -> list[DefenseConfig]:
    grid = [(1, 5), (1, 8), (4, 5), (6, 4), (8, 3), (10, 3)]
    return [
        DefenseConfig(
            family="rate-based",
            label=f"WindowedRateLimit(w={w}, cap={cap})",
            env={"AEGIS_DEF": "windowed", "AEGIS_WINDOW": w, "AEGIS_CAP": cap},
        )
        for (w, cap) in grid
    ]


def _behavioral_family() -> list[DefenseConfig]:
    return [
        DefenseConfig(
            family="behavioral",
            label="PerAddressInvariant (per-tx balance)",
            env={"AEGIS_DEF": "peraddr"},
            structural=True,
        )
    ]


def _fixed_anchor_family() -> list[DefenseConfig]:
    return [
        DefenseConfig(
            family="fixed-anchor",
            label=f"PriceDeviationGuard(<= {bps}bps)",
            env={"AEGIS_GUARD": "fixed", "AEGIS_DEVBPS": bps},
        )
        for bps in (300, 500, 609, 800, 1200)
    ]


def _lagged_oracle_family() -> list[DefenseConfig]:
    return [
        DefenseConfig(
            family="lagged-oracle",
            label=f"LaggedOracleGuard(<= {bps}bps)",
            env={"AEGIS_GUARD": "lagged", "AEGIS_DEVBPS": bps},
            structural=True,
        )
        for bps in (300, 500, 800)
    ]


# --------------------------------------------------------------------------- #
# The registry
# --------------------------------------------------------------------------- #
SCENARIOS: dict[str, Scenario] = {
    "reentrancy": Scenario(
        id="01",
        key="reentrancy",
        title="Reentrancy drain",
        summary=(
            "A reentrancy-drainable ETH vault. The attacker re-enters withdraw() "
            "to drain funds; a patient attacker bleeds slowly to evade a per-block "
            "rate limit. Rate caps overfit to a drain rate; a per-address per-tx "
            "balance invariant stops every rate."
        ),
        match_test="test_matchup",
        json_file="matchup.json",
        attacker_knob="AEGIS_TAKE",
        attacker_grid=[2, 3, 4, 5, 7, 11],
        benign_total=4,
        static_env={"AEGIS_HORIZON": 12},
        families={
            "rate-based": _rate_family(),
            "behavioral": _behavioral_family(),
        },
    ),
    "oracle": Scenario(
        id="02",
        key="oracle",
        title="Oracle / price manipulation",
        summary=(
            "A lending pool values collateral at an AMM spot price. The attacker "
            "pumps spot within one transaction and over-borrows. A fixed price "
            "anchor cannot tell a small same-block pump from organic drift; a "
            "one-block-lagged oracle stops any single-block manipulation."
        ),
        match_test="test_matchup02",
        json_file="matchup02.json",
        attacker_knob="AEGIS_PUMP",
        attacker_grid=[2, 3, 5, 10, 100],
        benign_total=2,
        families={
            "fixed-anchor": _fixed_anchor_family(),
            "lagged-oracle": _lagged_oracle_family(),
        },
    ),
}


def all_scenarios() -> list[Scenario]:
    return list(SCENARIOS.values())


def get(key: str) -> Scenario:
    if key not in SCENARIOS:
        raise KeyError(f"unknown scenario '{key}'; known: {sorted(SCENARIOS)}")
    return SCENARIOS[key]
