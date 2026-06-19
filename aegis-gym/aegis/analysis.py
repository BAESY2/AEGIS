"""Scenario-agnostic analyses built on the registry.

Three studies, each reusable across every registered vulnerability class:

  * ``leaderboard`` — rank every defense config by worst-case reward over the
    full attacker grid (the production-relevant metric: how bad is your worst
    day against any attacker in the family).
  * ``generalization`` — train on a subset of attackers, freeze the best config,
    test on the held-out attackers; report the train/test gap. This is the
    headline result: structural defenses transfer, threshold defenses overfit.
  * ``coevolution`` — an attacker/defender arms race over the verifiable reward.

All scoring goes through ``Scenario.score`` (i.e. the EVM). Results are cached
in-process so repeated reads of the same matchup don't re-run forge.
"""
from __future__ import annotations

from dataclasses import dataclass

from .registry import DefenseConfig, MatchResult, Scenario


class ScoreCache:
    """Memoize (scenario, config-label, attacker) -> MatchResult across a run."""

    def __init__(self) -> None:
        self._cache: dict[tuple, MatchResult] = {}

    def score(self, scenario: Scenario, config: DefenseConfig, attacker: int) -> MatchResult:
        key = (scenario.key, config.label, attacker)
        if key not in self._cache:
            self._cache[key] = scenario.score(config, attacker)
        return self._cache[key]


# --------------------------------------------------------------------------- #
# Leaderboard
# --------------------------------------------------------------------------- #
@dataclass
class LeaderboardRow:
    scenario: str
    family: str
    label: str
    structural: bool
    worst_case_saved: float
    worst_case_reward: float
    mean_saved: float
    fp: int
    benign_total: int


def configs_of(scenario: Scenario) -> list[DefenseConfig]:
    return [c for fam in scenario.families.values() for c in fam]


def evaluate_config(
    scenario: Scenario, config: DefenseConfig, cache: ScoreCache, attackers=None
) -> LeaderboardRow:
    grid = attackers if attackers is not None else scenario.attacker_grid
    results = [cache.score(scenario, config, a) for a in grid]
    saved = [r.saved for r in results]
    rewards = [r.reward for r in results]
    fp = results[0].fp
    return LeaderboardRow(
        scenario=scenario.key,
        family=config.family,
        label=config.label,
        structural=config.structural,
        worst_case_saved=min(saved),
        worst_case_reward=min(rewards),
        mean_saved=sum(saved) / len(saved),
        fp=fp,
        benign_total=scenario.benign_total,
    )


def leaderboard(scenario: Scenario, cache: ScoreCache | None = None) -> list[LeaderboardRow]:
    cache = cache or ScoreCache()
    rows = [evaluate_config(scenario, c, cache) for c in configs_of(scenario)]
    rows.sort(key=lambda r: (r.worst_case_reward, r.worst_case_saved), reverse=True)
    return rows


# --------------------------------------------------------------------------- #
# Train / test generalization
# --------------------------------------------------------------------------- #
@dataclass
class GeneralizationRow:
    scenario: str
    family: str
    trained_label: str
    structural: bool
    train: float
    test: float
    gap: float


def _split(grid: list[int]) -> tuple[list[int], list[int]]:
    """Split an attacker grid into TRAIN (stronger) and TEST (weaker) halves.

    We train on the strongest attackers and test on the weakest. Threshold
    defenses tuned against strong attacks fail precisely on the subtle/weak
    ones (a small pump looks like organic drift; a slow bleed looks legit),
    so this split is the hardest honest test of generalization.
    """
    ordered = sorted(grid, reverse=True)
    half = (len(ordered) + 1) // 2
    train = sorted(ordered[:half])
    test = sorted(ordered[half:])
    return train, test


def best_response(
    scenario: Scenario, family: list[DefenseConfig], train: list[int], cache: ScoreCache
) -> tuple[DefenseConfig, float]:
    """Pick the config maximizing worst-case reward over the TRAIN attackers."""
    best, best_wc = None, -1e9
    for cfg in family:
        wc = min(cache.score(scenario, cfg, a).reward for a in train)
        if wc > best_wc:
            best, best_wc = cfg, wc
    return best, best_wc


def generalization(scenario: Scenario, cache: ScoreCache | None = None) -> list[GeneralizationRow]:
    cache = cache or ScoreCache()
    train, test = _split(scenario.attacker_grid)
    rows: list[GeneralizationRow] = []
    for fam_name, family in scenario.families.items():
        cfg, train_wc = best_response(scenario, family, train, cache)
        test_wc = min(cache.score(scenario, cfg, a).reward for a in test)
        rows.append(
            GeneralizationRow(
                scenario=scenario.key,
                family=fam_name,
                trained_label=cfg.label,
                structural=cfg.structural,
                train=round(train_wc, 3),
                test=round(test_wc, 3),
                gap=round(train_wc - test_wc, 3),
            )
        )
    return rows, train, test


# --------------------------------------------------------------------------- #
# Co-evolution arms race
# --------------------------------------------------------------------------- #
@dataclass
class ArmsRaceStep:
    round: int
    population: list[int]
    defender_label: str
    worst_case_reward: float
    attacker_escalation: int


def coevolve(scenario: Scenario, family_name: str, cache: ScoreCache | None = None):
    """Run an arms race for one (threshold) defense family.

    The defender best-responds to the current attacker population; the attacker
    adds the strength that most reduces the defender's saved fraction. Returns
    the history, the naive (fast-attacker-only) baseline, and the co-evolved
    defender — each evaluated worst-case over the full attacker grid.
    """
    cache = cache or ScoreCache()
    family = scenario.families[family_name]
    grid = scenario.attacker_grid
    strongest = max(grid)

    def defender_for(pop: list[int]) -> DefenseConfig:
        return max(family, key=lambda c: min(cache.score(scenario, c, a).reward for a in pop))

    history: list[ArmsRaceStep] = []
    pop = [strongest]
    for rnd in range(1, len(grid) + 2):
        d = defender_for(pop)
        wc = min(cache.score(scenario, d, a).reward for a in pop)
        escalation = min(grid, key=lambda a: cache.score(scenario, d, a).saved)
        history.append(ArmsRaceStep(rnd, pop.copy(), d.label, round(wc, 3), escalation))
        if escalation in pop:
            break
        pop.append(escalation)

    coevolved = defender_for(pop)
    naive = max(family, key=lambda c: (cache.score(scenario, c, strongest).reward,))

    def worst_saved(cfg: DefenseConfig) -> float:
        return min(cache.score(scenario, cfg, a).saved for a in grid)

    return {
        "history": history,
        "naive": naive,
        "naive_worstcase_saved": round(worst_saved(naive), 3),
        "coevolved": coevolved,
        "coevolved_worstcase_saved": round(worst_saved(coevolved), 3),
    }
