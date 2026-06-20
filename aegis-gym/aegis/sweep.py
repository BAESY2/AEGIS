"""Dataset generation — turn the environment into a compounding labeled corpus.

Every matchup is an EVM-verified, label-free training example:
    features = (scenario, defense family, defense parameters, attacker strength)
    labels   = (funds saved, false positives, reward)

`sweep()` samples broadly over each scenario's parameter space — far beyond the
curated leaderboard grids — running each point on the EVM (Foundry) and appending
the outcome to a JSONL corpus. The result is a real ML dataset (e.g. to train a
"will this defense hold?" classifier) and the concrete form of the data moat:
the more scenarios and matches played, the larger and more valuable the corpus.

Generation is deterministic (seeded), append-only, and de-duplicated, so batches
compose into one growing corpus.
"""
from __future__ import annotations

import json
import random
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable

from . import foundry

ROOT = Path(__file__).resolve().parents[2]
DATA_DIR = ROOT / "data"
CORPUS = DATA_DIR / "trajectories.jsonl"
CARD = DATA_DIR / "DATASET.md"


@dataclass(frozen=True)
class Space:
    scenario: str
    match_test: str
    json_file: str
    attacker_knob: str
    attackers: list[int]
    static_env: dict
    families: list[dict]  # each: {name, structural, sample(rng)->env-dict}


def _spaces() -> list[Space]:
    return [
        Space(
            scenario="reentrancy",
            match_test="test_matchup",
            json_file="matchup.json",
            attacker_knob="AEGIS_TAKE",
            attackers=list(range(2, 12)),
            static_env={"AEGIS_HORIZON": 12},
            families=[
                {
                    "name": "rate-based",
                    "structural": False,
                    "sample": lambda r: {
                        "AEGIS_DEF": "windowed",
                        "AEGIS_WINDOW": r.randint(1, 12),
                        "AEGIS_CAP": r.randint(1, 12),
                    },
                },
                {
                    "name": "behavioral",
                    "structural": True,
                    "sample": lambda r: {"AEGIS_DEF": r.choice(["peraddr", "lock"])},
                },
            ],
        ),
        Space(
            scenario="oracle",
            match_test="test_matchup02",
            json_file="matchup02.json",
            attacker_knob="AEGIS_PUMP",
            attackers=[2, 3, 4, 5, 7, 10, 20, 50, 100, 200],
            static_env={},
            families=[
                {
                    "name": "fixed-anchor",
                    "structural": False,
                    "sample": lambda r: {"AEGIS_GUARD": "fixed", "AEGIS_DEVBPS": r.randint(100, 2000)},
                },
                {
                    "name": "lagged-oracle",
                    "structural": True,
                    "sample": lambda r: {"AEGIS_GUARD": "lagged", "AEGIS_DEVBPS": r.randint(100, 2000)},
                },
            ],
        ),
        Space(
            scenario="access",
            match_test="test_matchup03",
            json_file="matchup03.json",
            attacker_knob="AEGIS_TAKE",
            attackers=list(range(2, 12)),
            static_env={"AEGIS_HORIZON": 12},
            families=[
                {
                    "name": "rate-based",
                    "structural": False,
                    "sample": lambda r: {
                        "AEGIS_DEF": "windowed",
                        "AEGIS_WINDOW": r.randint(1, 12),
                        "AEGIS_CAP": r.randint(1, 12),
                    },
                },
                {
                    "name": "identity",
                    "structural": True,
                    "sample": lambda r: {"AEGIS_DEF": "owneronly"},
                },
            ],
        ),
        Space(
            scenario="governance",
            match_test="test_matchup04",
            json_file="matchup04.json",
            attacker_knob="AEGIS_TAKE",
            attackers=[100, 120, 150, 200, 300, 500, 1000, 2500, 5000],
            static_env={},
            families=[
                {
                    "name": "vote-cap",
                    "structural": False,
                    "sample": lambda r: {"AEGIS_DEF": "maxvotes", "AEGIS_CAP": r.choice([100, 120, 150, 200, 250, 400, 800, 2000, 6000])},
                },
                {
                    "name": "snapshot",
                    "structural": True,
                    "sample": lambda r: {"AEGIS_DEF": "snapshot"},
                },
            ],
        ),
    ]


def _existing_keys() -> set:
    keys = set()
    if CORPUS.exists():
        for line in CORPUS.read_text().splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
                keys.add(json.dumps([rec["scenario"], rec["params"], rec["attacker"], rec["family"]], sort_keys=True))
            except (json.JSONDecodeError, KeyError):
                continue
    return keys


def sweep(budget: int = 200, seed: int = 0, on_progress: Callable[[int, int], None] | None = None) -> int:
    """Run up to `budget` *new* distinct matchups across all scenarios; append
    each EVM-verified outcome to the corpus. Returns the number of new records."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    spaces = _spaces()
    rng = random.Random(seed)
    seen = _existing_keys()
    written = 0
    attempts = 0
    max_attempts = budget * 12  # give up if the space is exhausted

    with CORPUS.open("a") as fh:
        while written < budget and attempts < max_attempts:
            attempts += 1
            space = rng.choice(spaces)
            fam = rng.choice(space.families)
            attacker = rng.choice(space.attackers)
            params = fam["sample"](rng)
            key = json.dumps([space.scenario, params, attacker, fam["name"]], sort_keys=True)
            if key in seen:
                continue
            seen.add(key)

            env = {**space.static_env, **params, space.attacker_knob: attacker}
            try:
                d = foundry.run_test(space.match_test, space.json_file, env)
            except RuntimeError:
                continue  # skip a transient/invalid point rather than abort the batch

            record = {
                "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "scenario": space.scenario,
                "family": fam["name"],
                "structural": fam["structural"],
                "params": params,
                "attacker": attacker,
                "saved": round(d["saved_frac_1e18"] / 1e18, 4),
                "fp": int(d["fp"]),
                "reward": round(d["reward_1e18"] / 1e18, 4),
            }
            fh.write(json.dumps(record) + "\n")
            fh.flush()
            written += 1
            if on_progress:
                on_progress(written, budget)
    return written


def read() -> list[dict]:
    if not CORPUS.exists():
        return []
    out = []
    for line in CORPUS.read_text().splitlines():
        line = line.strip()
        if line:
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return out


def stats(records: list[dict] | None = None) -> dict:
    records = records if records is not None else read()
    by_scenario: dict[str, dict] = {}
    pos = 0
    for r in records:
        s = by_scenario.setdefault(r["scenario"], {"n": 0, "families": {}})
        s["n"] += 1
        fam = s["families"].setdefault(r["family"], {"n": 0, "structural": r.get("structural", False)})
        fam["n"] += 1
        if r["reward"] > 0:
            pos += 1
    return {
        "total": len(records),
        "positive_reward": pos,
        "negative_or_zero_reward": len(records) - pos,
        "scenarios": by_scenario,
    }


def write_card(path: Path | None = None) -> Path:
    path = path or CARD
    s = stats()
    lines = [
        "# Aegis trajectory dataset",
        "",
        "An EVM-verified, label-free corpus of smart-contract defense matchups. "
        "Every record is produced by contract execution on a forked chain "
        "(Foundry) — no human labels, no Python heuristics. This is the concrete "
        "form of the project's data asset: each scenario added and each match "
        "played enlarges it.",
        "",
        f"- **Records:** {s['total']}",
        f"- **Positive-reward (precise) matchups:** {s['positive_reward']}",
        f"- **Zero/negative-reward matchups:** {s['negative_or_zero_reward']}",
        "- **Provenance:** deterministic; regenerate/extend with "
        "`cd aegis-gym && python3 -m aegis dataset --budget N --seed S`.",
        "",
        "## Per-scenario coverage",
        "",
        "| Scenario | Records | Families (n) |",
        "|----------|:-------:|--------------|",
    ]
    for key, sc in sorted(s["scenarios"].items()):
        fams = ", ".join(
            f"{'*' if f['structural'] else ''}{name} ({f['n']})"
            for name, f in sc["families"].items()
        )
        lines.append(f"| {key} | {sc['n']} | {fams} |")
    lines += [
        "",
        "`*` = structural / invariant-based defense.",
        "",
        "## Schema (one JSON object per line, `trajectories.jsonl`)",
        "",
        "```json",
        '{"ts": "...", "scenario": "reentrancy", "family": "rate-based",',
        ' "structural": false, "params": {"AEGIS_DEF": "windowed", "AEGIS_WINDOW": 8, "AEGIS_CAP": 3},',
        ' "attacker": 2, "saved": 0.7, "fp": 1, "reward": 0.45}',
        "```",
        "",
        "- `params` are the scenario-specific defense knobs (the features).",
        "- `attacker` is the attacker-strength axis for the scenario.",
        "- `saved` ∈ [0,1], `fp` is the false-positive count, `reward` ∈ [-1,1] "
        "(the EVM-derived label).",
        "",
        "## Suggested tasks",
        "",
        "- **Defense-outcome prediction:** features → `reward` (regression) or "
        "`reward > 0` (classification): \"will this defense hold?\"",
        "- **Robust-config search:** learn the configuration maximizing worst-case "
        "reward over the attacker axis (what `aegis train` does online).",
        "- **Generalization study:** train on a subset of attackers/scenarios, "
        "test on held-out ones (structural vs threshold).",
        "",
        "License: MIT (same as the repository).",
    ]
    path.write_text("\n".join(lines) + "\n")
    return path
