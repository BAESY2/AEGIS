"""Score a user-submitted defense (submissions/Submission.sol) and rank it.

The local form of the hosted "submit a defense, get scored, climb the board"
loop: a contributor edits submissions/Submission.sol, runs `aegis submit`, and
gets their worst-case reward across the scenario's attacker grid plus the rank
they'd take on the leaderboard — no registry edits. Run for many contributors,
this is the mechanism that accumulates the multi-party dataset moat.

Currently wired for the reentrancy scenario (the flagship); the same pattern
extends to the others.
"""
from __future__ import annotations

from . import analysis, foundry, registry


def run(scenario_key: str = "reentrancy") -> dict:
    if scenario_key != "reentrancy":
        raise RuntimeError("the submission harness is currently wired for 'reentrancy'")
    sc = registry.get(scenario_key)
    horizon = sc.static_env.get("AEGIS_HORIZON", 12)

    rows = []
    for take in sc.attacker_grid:
        d = foundry.run_test("test_submit", "submission.json", {"AEGIS_TAKE": take, "AEGIS_HORIZON": horizon})
        rows.append({
            "attacker": take,
            "saved": d["saved_frac_1e18"] / 1e18,
            "fp": int(d["fp"]),
            "reward": d["reward_1e18"] / 1e18,
        })
    worst_saved = min(r["saved"] for r in rows)
    worst_reward = min(r["reward"] for r in rows)
    fp = rows[0]["fp"]

    # rank against the reference leaderboard (by worst-case reward)
    board = analysis.leaderboard(sc, analysis.ScoreCache())
    better = sum(1 for r in board if r.worst_case_reward > worst_reward + 1e-9)
    rank = better + 1

    return {
        "scenario": scenario_key,
        "rows": rows,
        "worst_case_saved": worst_saved,
        "worst_case_reward": worst_reward,
        "fp": fp,
        "benign_total": sc.benign_total,
        "rank": rank,
        "field": len(board) + 1,
        "leaderboard_best": board[0].worst_case_reward if board else None,
    }
