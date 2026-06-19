"""Scenario 02 (oracle manipulation) frontier reproduction.

Mirrors frontier.py for the price-guard family: shows that a fixed-anchor guard
cannot both pass organic drift and stop a small same-block pump, while a
one-block-lagged oracle guard crosses that floor. Scored through the Foundry
matchup02 harness.
"""
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MJSON = ROOT / "scoring" / "matchup02.json"
BIN = str(Path.home() / ".foundry" / "bin")
PUMPS = [3, 5, 10, 100]


def score(guard, devbps, pump):
    p = os.environ.get("PATH", "")
    if BIN not in p:
        p = f"{p}:{BIN}"
    env = {**os.environ, "PATH": p, "AEGIS_GUARD": guard,
           "AEGIS_DEVBPS": str(devbps), "AEGIS_PUMP": str(pump)}
    subprocess.run(["forge", "test", "--match-test", "test_matchup02", "-q"],
                   cwd=ROOT, check=True, capture_output=True, env=env)
    d = json.loads(MJSON.read_text())
    return d["saved_frac_1e18"] / 1e18, d["fp"]


def main():
    print(f"saved fraction over pump sizes {PUMPS} eth (FP out of 2 honest borrows)\n")
    print("  defense".ljust(32) + "".join(f"{p:>7}" for p in PUMPS) + "   fp")
    for label, guard, dev in [
        ("fixed-anchor (<=609bps)", "fixed", 609),
        ("fixed-anchor (<=300bps)", "fixed", 300),
        ("lagged-oracle (<=300bps)", "lagged", 300),
    ]:
        cells, fp = [], 0
        for pump in PUMPS:
            s, fp = score(guard, dev, pump)
            cells.append(s)
        row = "".join(f"{c:>7.2f}" for c in cells)
        print(f"  {label:<30}{row}   {fp}/2")
    print("\nfixed-anchor hits a floor (small pump ~ organic drift); the lagged")
    print("oracle crosses it: same-block manipulation cannot move the lagged price.")


if __name__ == "__main__":
    main()
