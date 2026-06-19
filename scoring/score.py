#!/usr/bin/env python3
"""Thin wrapper: run the Aegis scorer and print the leaderboard.

Usage:  python scoring/score.py
Reads scoring/results.json (written by `forge test`) and renders a ranking.
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESULTS = ROOT / "scoring" / "results.json"


def main() -> int:
    print("running forge test ...")
    proc = subprocess.run(["forge", "test"], cwd=ROOT)
    if proc.returncode != 0:
        print("forge test failed", file=sys.stderr)
        return proc.returncode

    data = json.loads(RESULTS.read_text())
    rows = sorted(data["results"], key=lambda r: r["reward_1e18"], reverse=True)

    print(f"\nleaderboard — scenario {data['scenario']}")
    print(f"{'rank':<5}{'defense':<14}{'reward':>8}")
    for i, r in enumerate(rows, 1):
        print(f"{i:<5}{r['defense']:<14}{r['reward_1e18'] / 1e18:>8.3f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
