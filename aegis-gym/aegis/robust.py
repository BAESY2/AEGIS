"""Robust (minimax) defense under attacker-type uncertainty.

The behavioral class showed the best defense DEPENDS on the attacker's stealth —
a parameter the defender cannot observe. This module treats that as a game: rows
are defenses, columns are attacker stealth levels, entries are the EVM-scored
reward. From the behavioral records in the corpus it computes:

  * the minimax (robust) defense — the one whose WORST case over attacker types
    is best, and the worst-case reward it guarantees;
  * the "oracle" defender that knows the stealth and plays the best response to
    each — an upper bound;
  * the regret of not knowing the attacker (oracle mean − robust mean), i.e. the
    value of attacker intelligence;
  * the best-response defense at each stealth level (the crossover).

It uses only data already in the corpus — no EVM calls.
"""
from __future__ import annotations

import json

from . import sweep


def _defense_key(rec: dict) -> str:
    p = rec.get("params", {})
    spec = str(p.get("AEGIS_DEF", p.get("AEGIS_GUARD", "")))
    extra = ""
    if "AEGIS_DEVBPS" in p:
        extra += f" {p['AEGIS_DEVBPS']}bps"
    if "AEGIS_WINDOW" in p:
        extra += f" w={p['AEGIS_WINDOW']}"
    if "AEGIS_CAP" in p:
        extra += f" cap={p['AEGIS_CAP']}"
    if "AEGIS_MAT" in p:
        extra += f" mat={p['AEGIS_MAT']}"
    return spec + extra


def payoff_matrix(scenario: str = "behavioral"):
    recs = [r for r in sweep.read() if r["scenario"] == scenario]
    stealths = sorted({r["attacker"] for r in recs})
    table: dict[str, dict] = {}
    for r in recs:
        table.setdefault(_defense_key(r), {})[r["attacker"]] = r["reward"]
    # keep only defenses with full coverage over the attacker axis
    full = {d: row for d, row in table.items() if all(s in row for s in stealths)}
    return full, stealths


def run(scenario: str = "behavioral") -> dict:
    table, stealths = payoff_matrix(scenario)
    if not table or not stealths:
        raise RuntimeError(
            "no covered defenses in the corpus for this scenario; "
            "generate data first (python3 -m aegis dataset)."
        )

    # minimax (robust) defense: maximize the worst case over attacker stealth
    worst = {d: min(row[s] for s in stealths) for d, row in table.items()}
    robust = max(worst, key=worst.get)
    robust_worst = worst[robust]
    robust_mean = sum(table[robust][s] for s in stealths) / len(stealths)

    # oracle (knows the stealth): best response per column
    oracle_best = {s: max(table[d][s] for d in table) for s in stealths}
    oracle_arg = {s: max(table, key=lambda d: table[d][s]) for s in stealths}
    oracle_mean = sum(oracle_best.values()) / len(stealths)

    regret = oracle_mean - robust_mean

    # crossover: distinct best-responses across the stealth axis
    crossover = []
    last = None
    for s in stealths:
        d = oracle_arg[s]
        if d != last:
            crossover.append({"stealth": s, "best_defense": d, "reward": round(table[d][s], 3)})
            last = d

    return {
        "scenario": scenario,
        "n_defenses": len(table),
        "stealths": stealths,
        "robust_defense": robust,
        "robust_worstcase": round(robust_worst, 3),
        "robust_mean": round(robust_mean, 3),
        "oracle_mean": round(oracle_mean, 3),
        "regret_of_not_knowing_attacker": round(regret, 3),
        "crossover": crossover,
    }
