"""Pareto frontier of defenses over (worst-case funds saved, false positives).

Two objectives a protocol actually trades off: maximize the worst-case fraction
of funds saved (over the attacker grid) and minimize false positives. A defense
is Pareto-optimal if no other defense saves at least as much with no more false
positives (and strictly better on one). Computed per scenario from the corpus.

The unifying result: in the classes with a clean structural answer the frontier
collapses to a SINGLE point (the structural defense dominates everything), while
in the behavioral 'no free lunch' class the frontier has MULTIPLE points — a
genuine recall/false-positive trade-off with no dominant defense.
"""
from __future__ import annotations

from . import sweep
from .robust import _defense_key


def _frontier(points: dict[str, tuple[float, int]]):
    """points: defense -> (saved, fp). Maximize saved, minimize fp."""
    items = list(points.items())
    front = []
    for d, (s, f) in items:
        dominated = any(
            (s2 >= s and f2 <= f) and (s2 > s or f2 < f) for d2, (s2, f2) in items if d2 != d
        )
        if not dominated:
            front.append((d, s, f))
    front.sort(key=lambda t: (-t[1], t[2]))
    return front


def run(scenario: str) -> dict:
    recs = [r for r in sweep.read() if r["scenario"] == scenario]
    if not recs:
        raise RuntimeError(f"no records for scenario '{scenario}'")
    # MEAN saved over the attacker axis (a genuine operating point, not a
    # degenerate worst case); fp is a property of the defense.
    agg: dict[str, list] = {}
    fp: dict[str, int] = {}
    for r in recs:
        d = _defense_key(r)
        agg.setdefault(d, []).append(r["saved"])
        fp[d] = max(fp.get(d, 0), int(r["fp"]))
    points = {d: (sum(v) / len(v), fp[d]) for d, v in agg.items()}
    front = _frontier(points)

    # de-duplicate ties: one representative per distinct (saved, fp) point
    seen = set()
    distinct = []
    for d, s, f in front:
        key = (round(s, 2), f)
        if key in seen:
            continue
        seen.add(key)
        distinct.append({"defense": d, "mean_saved": round(s, 3), "fp": f})
    return {"scenario": scenario, "n_defenses": len(points), "frontier": distinct}


def run_all() -> dict:
    scenarios = sorted({r["scenario"] for r in sweep.read()})
    return {s: run(s) for s in scenarios}
