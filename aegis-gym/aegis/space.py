"""Quantify the combinatorial size of the benchmark's configuration space.

A handful of hand-written scenarios is misleading: once you count parameter
ranges, attacker strengths, and — above all — defense *compositions* (every
subset of compatible primitives is a valid defense-in-depth stack), the number
of distinct, EVM-scorable matchups is enormous. This module computes that number
from explicit, auditable axis cardinalities, so the shipped dataset can be seen
for what it is: a tiny sample of a ~10^N space.

The composition count uses the exact identity: the number of distinct non-empty
AND-stacks over primitives with parameter cardinalities c_1..c_k is
    prod_i (c_i + 1) - 1
(each primitive is absent, or present with one of c_i settings).
"""
from __future__ import annotations

from dataclasses import dataclass
from math import log10, prod


@dataclass(frozen=True)
class ScenarioSpace:
    key: str
    # defense primitives -> number of distinct parameter settings each
    primitives: dict          # name -> cardinality
    attacker_card: int        # distinct attacker strengths
    modes: int = 2            # AND (defense-in-depth) and OR (fallback) stacks

    def singleton_defenses(self) -> int:
        return sum(self.primitives.values())

    def composite_defenses(self) -> int:
        # non-empty stacks over the primitives, parameter-expanded, x modes
        base = prod(c + 1 for c in self.primitives.values()) - 1
        # modes only multiply stacks of size >= 2; size-1 stacks are the singletons.
        singles = self.singleton_defenses()
        multi = base - singles
        return singles + multi * self.modes

    def total(self) -> int:
        return self.composite_defenses() * self.attacker_card


# Explicit, auditable cardinalities (parameter ranges the matchup scorers accept).
# Structural defenses have no parameters (cardinality 1).
SPACES: list[ScenarioSpace] = [
    ScenarioSpace(
        key="reentrancy",
        primitives={"windowed(window 1-64 x cap 1-64)": 64 * 64, "peraddr": 1, "lock": 1},
        attacker_card=64,  # take 1-64
    ),
    ScenarioSpace(
        key="oracle",
        primitives={"fixed-anchor(1-2000bps)": 2000, "lagged(1-2000bps)": 2000},
        attacker_card=1000,  # pump 1-1000
    ),
    ScenarioSpace(
        key="access",
        primitives={"windowed(window 1-64 x cap 1-64)": 64 * 64, "owneronly": 1},
        attacker_card=64,
    ),
    ScenarioSpace(
        key="governance",
        primitives={"maxvotes(1-10000)": 10000, "snapshot": 1},
        attacker_card=100000,  # flash-borrow size
    ),
    ScenarioSpace(
        key="behavioral",
        primitives={"amount-cap(1-64)": 64, "new-destination": 1, "behavioral(1-64)": 64},
        attacker_card=100,  # attacker behavior profiles
    ),
]


def report(dataset_size: int = 0) -> dict:
    rows = []
    grand = 0
    for s in SPACES:
        t = s.total()
        grand += t
        rows.append(
            {
                "scenario": s.key,
                "singleton_defenses": s.singleton_defenses(),
                "composite_defenses": s.composite_defenses(),
                "attacker_strengths": s.attacker_card,
                "matchups": t,
            }
        )
    out = {
        "rows": rows,
        "total_matchups": grand,
        "log10": log10(grand) if grand else 0,
        "dataset_size": dataset_size,
        "coverage_fraction": (dataset_size / grand) if grand else 0.0,
    }
    return out
