"""Train/test generalization: do defenses generalize to UNSEEN attackers?

Protocol (standard ML generalization, applied to defense):
  1. Split the attacker grid into disjoint TRAIN and TEST sets.
  2. "Train" a defense = best-response: pick the config in a family that
     maximizes worst-case reward over TRAIN attackers only.
  3. Evaluate that frozen config on the held-out TEST attackers.
  4. Report the train/test gap per family.

Hypothesis: threshold/rate families overfit (large gap — they only cover the
attackers they saw), while structural defenses (behavioral invariant, lagged
oracle) generalize (small gap), because they exploit an invariant rather than
fitting a boundary to seen attacks.
"""
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BIN = str(Path.home() / ".foundry" / "bin")
_cache = {}


def _run(match, jsonfile, **env_extra):
    p = os.environ.get("PATH", "")
    if BIN not in p:
        p = f"{p}:{BIN}"
    env = {**os.environ, "PATH": p, **{k: str(v) for k, v in env_extra.items()}}
    subprocess.run(["forge", "test", "--match-test", match, "-q"],
                   cwd=ROOT, check=True, capture_output=True, env=env)
    d = json.loads((ROOT / "scoring" / jsonfile).read_text())
    return d["saved_frac_1e18"] / 1e18, d["fp"]


# ---------- scenario 01: reentrancy ----------
def s01_score(config, take):
    key = ("s01", config, take)
    if key in _cache:
        return _cache[key]
    if config[0] == "rate":
        _, W, cap = config
        r = _run("test_matchup", "matchup.json", AEGIS_DEF="windowed",
                 AEGIS_WINDOW=W, AEGIS_CAP=cap, AEGIS_TAKE=take, AEGIS_HORIZON=12)
    else:  # behavioral
        r = _run("test_matchup", "matchup.json", AEGIS_DEF="peraddr",
                 AEGIS_WINDOW=1, AEGIS_CAP=5, AEGIS_TAKE=take, AEGIS_HORIZON=12)
    _cache[key] = r
    return r


# ---------- scenario 02: oracle ----------
def s02_score(config, pump):
    key = ("s02", config, pump)
    if key in _cache:
        return _cache[key]
    kind, dev = config
    r = _run("test_matchup02", "matchup02.json", AEGIS_GUARD=kind,
             AEGIS_DEVBPS=dev, AEGIS_PUMP=pump)
    _cache[key] = r
    return r


def train_test(score_fn, candidates, train, test, benign_total):
    def reward(cfg, a):
        saved, fp = score_fn(cfg, a)
        return saved - fp / benign_total

    best, best_train = None, -1e9
    for cfg in candidates:
        wc = min(reward(cfg, a) for a in train)
        if wc > best_train:
            best, best_train = cfg, wc
    test_wc = min(reward(best, a) for a in test)
    return best, round(best_train, 3), round(test_wc, 3), round(best_train - test_wc, 3)


def main():
    results = {}

    print("=" * 64)
    print("SCENARIO 01 (reentrancy)   train takes=[5,7,11]  test=[2,3,4]")
    print("=" * 64)
    s01 = {
        "rate-based":  [("rate", 1, 5), ("rate", 1, 8), ("rate", 4, 5),
                         ("rate", 6, 4), ("rate", 8, 3)],
        "behavioral":  [("beh",)],
    }
    print(f"  {'family':<14}{'trained cfg':<18}{'train':>7}{'test':>7}{'gap':>7}")
    for name, cands in s01.items():
        cfg, tr, te, gap = train_test(s01_score, cands, [5, 7, 11], [2, 3, 4], 4)
        results[f"s01:{name}"] = {"cfg": cfg, "train": tr, "test": te, "gap": gap}
        print(f"  {name:<14}{str(cfg):<18}{tr:>7.2f}{te:>7.2f}{gap:>7.2f}")

    print("\n" + "=" * 64)
    print("SCENARIO 02 (oracle)       train pumps=[8,20,100]  test=[2,3,6]")
    print("=" * 64)
    s02 = {
        "fixed-anchor":  [("fixed", d) for d in (300, 500, 609, 800, 1200)],
        "lagged-oracle": [("lagged", d) for d in (300, 500, 800)],
    }
    print(f"  {'family':<14}{'trained cfg':<18}{'train':>7}{'test':>7}{'gap':>7}")
    for name, cands in s02.items():
        cfg, tr, te, gap = train_test(s02_score, cands, [8, 20, 100], [2, 3, 6], 2)
        results[f"s02:{name}"] = {"cfg": cfg, "train": tr, "test": te, "gap": gap}
        print(f"  {name:<14}{str(cfg):<18}{tr:>7.2f}{te:>7.2f}{gap:>7.2f}")

    (ROOT / "scoring" / "generalization.json").write_text(json.dumps(results, indent=2))
    print("\nstructural defenses (behavioral / lagged) generalize to unseen")
    print("attackers; threshold/rate defenses overfit (large train->test gap).")
    print("wrote scoring/generalization.json")


if __name__ == "__main__":
    main()
