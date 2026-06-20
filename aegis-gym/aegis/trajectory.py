"""The compounding trajectory ledger.

Every matchup scored on the EVM is appended as one JSON line to
``scoring/trajectories.jsonl``. This is the dataset asset the project is built
around: each match played in the environment — by the leaderboard, the
generalization study, the co-evolution loop, or a contributor scoring a
submission — leaves behind a labeled (defense, attacker, outcome) record that
accumulates over time.

Logging is best-effort and never interferes with scoring: any I/O error is
swallowed. Set ``AEGIS_NO_TRAJECTORY=1`` to disable it (e.g. in tight loops).
"""
from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path

LEDGER = Path(__file__).resolve().parents[2] / "scoring" / "trajectories.jsonl"


def enabled() -> bool:
    return os.environ.get("AEGIS_NO_TRAJECTORY", "") not in ("1", "true", "True")


def log(scenario_key: str, config, attacker, result) -> None:
    """Append one matchup outcome to the ledger (best-effort)."""
    if not enabled():
        return
    record = {
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "scenario": scenario_key,
        "family": config.family,
        "defense": config.label,
        "structural": config.structural,
        "attacker": attacker,
        "saved": round(result.saved, 4),
        "fp": result.fp,
        "benign_total": result.benign_total,
        "reward": round(result.reward, 4),
    }
    try:
        LEDGER.parent.mkdir(parents=True, exist_ok=True)
        with LEDGER.open("a") as fh:
            fh.write(json.dumps(record) + "\n")
    except OSError:
        pass  # logging must never break scoring


def read() -> list[dict]:
    if not LEDGER.exists():
        return []
    out = []
    for line in LEDGER.read_text().splitlines():
        line = line.strip()
        if line:
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return out


def summary() -> dict:
    """Aggregate the ledger into per-scenario / per-family statistics."""
    records = read()
    by_scenario: dict[str, dict] = {}
    for r in records:
        s = by_scenario.setdefault(
            r["scenario"], {"matchups": 0, "families": {}}
        )
        s["matchups"] += 1
        fam = s["families"].setdefault(
            r["family"], {"n": 0, "wins": 0, "structural": r.get("structural", False)}
        )
        fam["n"] += 1
        if r["reward"] > 0:
            fam["wins"] += 1
    return {"total_matchups": len(records), "scenarios": by_scenario}
