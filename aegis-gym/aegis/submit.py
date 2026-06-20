"""Score a user-submitted defense and rank it — for ANY scenario.

A contributor (or a protocol team) edits the submission slot for the class they
care about — submissions/<scenario>/Submission.sol — and runs `aegis submit
<scenario>`. The harness scores it on that scenario's attacker grid and reports
the worst-case reward plus, where a reference leaderboard exists, the rank. Run
across many contributors, this is the mechanism that accumulates the multi-party
dataset moat.

Wired for all five classes; the reentrancy slot is `submissions/Submission.sol`,
the others are `submissions/<scenario>/Submission.sol`.
"""
from __future__ import annotations

from . import analysis, foundry, registry

# scenario -> (match_test, json_file, attacker_knob, grid, submission_env)
SCORERS = {
    "reentrancy": ("test_submit", "submission.json", "AEGIS_TAKE", [2, 3, 4, 5, 7, 11], {"AEGIS_HORIZON": 12}),
    "oracle": ("test_matchup02", "matchup02.json", "AEGIS_PUMP", [2, 3, 5, 10, 100], {"AEGIS_GUARD": "submission"}),
    "access": ("test_matchup03", "matchup03.json", "AEGIS_TAKE", [2, 3, 4, 5, 7, 11], {"AEGIS_DEF": "submission", "AEGIS_HORIZON": 12}),
    "governance": ("test_matchup04", "matchup04.json", "AEGIS_TAKE", [100, 150, 300, 1000, 5000], {"AEGIS_DEF": "submission"}),
    "behavioral": ("test_matchup05", "matchup05.json", "AEGIS_STEALTH", [0, 15, 30, 45, 60, 75, 90, 100], {"AEGIS_DEF": "submission"}),
}


def run(scenario_key: str = "reentrancy") -> dict:
    if scenario_key not in SCORERS:
        raise RuntimeError(f"unknown scenario '{scenario_key}'; options: {sorted(SCORERS)}")
    match_test, json_file, knob, grid, sub_env = SCORERS[scenario_key]

    rows = []
    for atk in grid:
        d = foundry.run_test(match_test, json_file, {**sub_env, knob: atk})
        rows.append({
            "attacker": atk,
            "saved": d["saved_frac_1e18"] / 1e18,
            "fp": int(d["fp"]),
            "reward": d["reward_1e18"] / 1e18,
        })
    worst_saved = min(r["saved"] for r in rows)
    worst_reward = min(r["reward"] for r in rows)
    fp = rows[0]["fp"]

    out = {
        "scenario": scenario_key,
        "rows": rows,
        "worst_case_saved": worst_saved,
        "worst_case_reward": worst_reward,
        "fp": fp,
        "rank": None,
        "field": None,
        "leaderboard_best": None,
    }

    # rank against the reference leaderboard, when this scenario is registered
    if scenario_key in registry.SCENARIOS:
        sc = registry.get(scenario_key)
        out["benign_total"] = sc.benign_total
        board = analysis.leaderboard(sc, analysis.ScoreCache())
        better = sum(1 for r in board if r.worst_case_reward > worst_reward + 1e-9)
        out["rank"] = better + 1
        out["field"] = len(board) + 1
        out["leaderboard_best"] = board[0].worst_case_reward if board else None
    return out
