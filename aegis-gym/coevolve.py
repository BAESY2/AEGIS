"""Co-evolution: an attacker and a defender escalate against each other over a
verifiable EVM reward, with no hand-set answer on either side.

Pipeline
  1. Build the saved-fraction matrix over a defender grid x attacker grid by
     running each matchup through the Foundry scorer (the EVM is the verifier).
  2. Run the arms race:
       - defender best-responds: pick (window, cap) maximizing WORST-CASE reward
         over the current attacker population;
       - attacker best-responds: add the drain rate that most evades that
         defender. Repeat until the attacker can find no new evasion.
  3. Contrast a defender tuned only on the fast attacker (the naive baseline)
     against the co-evolved defender, on the full attacker grid.
"""
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MJSON = ROOT / "scoring" / "matchup.json"
BIN = str(Path.home() / ".foundry" / "bin")
HORIZON = 12

DEFENDERS = [(1, 5), (1, 8), (4, 5), (6, 4), (8, 3), (10, 3)]  # (window, cap)
ATTACKERS = [2, 3, 4, 5, 7, 11]                                # takePerBlock (eth)


def _env(**kw):
    p = os.environ.get("PATH", "")
    if BIN not in p:
        p = f"{p}:{BIN}"
    return {**os.environ, "PATH": p, **{k: str(v) for k, v in kw.items()}}


def run_matchup(W, cap, take):
    subprocess.run(
        ["forge", "test", "--match-test", "test_matchup", "-q"],
        cwd=ROOT, check=True, capture_output=True,
        env=_env(AEGIS_WINDOW=W, AEGIS_CAP=cap, AEGIS_TAKE=take, AEGIS_HORIZON=HORIZON),
    )
    d = json.loads(MJSON.read_text())
    return d["saved_frac_1e18"] / 1e18, d["fp"]


def build_matrix():
    saved, fp = {}, {}
    for (W, cap) in DEFENDERS:
        for take in ATTACKERS:
            s, f = run_matchup(W, cap, take)
            saved[((W, cap), take)] = s
            fp[(W, cap)] = f
    return saved, fp


def reward(saved, fp, d, a):
    return saved[(d, a)] - fp[d] / 4.0


def best_defender(saved, fp, pop):
    return max(DEFENDERS, key=lambda d: min(reward(saved, fp, d, a) for a in pop))


def worst_case_saved(saved, d, pop):
    return min(saved[(d, a)] for a in pop)


def main():
    print("building matchup matrix (forge) ...")
    saved, fp = build_matrix()

    print("\nsaved-fraction matrix (rows=defender (W,cap), cols=attacker take):")
    header = "  (W,cap)\\take " + "".join(f"{a:>6}" for a in ATTACKERS) + "   fp"
    print(header)
    for d in DEFENDERS:
        row = "".join(f"{saved[(d,a)]:>6.2f}" for a in ATTACKERS)
        print(f"  {str(d):>11} {row}   {fp[d]}/4")

    # ---- arms race ----
    print("\narms race:")
    pop = [11]  # the attacker starts fast/greedy
    history = []
    for rnd in range(1, len(ATTACKERS) + 2):
        d = best_defender(saved, fp, pop)
        wc = min(reward(saved, fp, d, a) for a in pop)
        a_star = min(ATTACKERS, key=lambda a: saved[(d, a)])  # best evasion
        history.append({"round": rnd, "pop": pop.copy(), "defender": d,
                        "worstcase_reward": round(wc, 3), "attacker_response": a_star})
        print(f"  round {rnd}: attackers={pop} -> defender={d} "
              f"(worst-case reward {wc:+.2f}); attacker escalates to take={a_star}")
        if a_star in pop:
            print("  -> attacker can find no new evasion. equilibrium.")
            break
        pop.append(a_star)

    coevolved = best_defender(saved, fp, pop)

    # ---- naive baseline: a defender tuned ONLY on the fast attacker ----
    naive = max(DEFENDERS, key=lambda d: (reward(saved, fp, d, 11), -d[0]))

    full = ATTACKERS
    naive_wc = worst_case_saved(saved, naive, full)
    coevo_wc = worst_case_saved(saved, coevolved, full)

    print("\nheadline (worst-case saved fraction over the FULL attacker grid):")
    print(f"  naive defender tuned on fast attacker only {naive}: {naive_wc:.2f}")
    print(f"  co-evolved defender                        {coevolved}: {coevo_wc:.2f}")
    print(f"  robustness gain: {coevo_wc - naive_wc:+.2f} worst-case saved")

    out = {
        "horizon": HORIZON, "defenders": DEFENDERS, "attackers": ATTACKERS,
        "saved": {f"{d}|{a}": saved[(d, a)] for d in DEFENDERS for a in ATTACKERS},
        "fp": {str(d): fp[d] for d in DEFENDERS},
        "arms_race": history,
        "naive_defender": naive, "naive_worstcase_saved": naive_wc,
        "coevolved_defender": coevolved, "coevolved_worstcase_saved": coevo_wc,
    }
    (ROOT / "scoring" / "coevolution.json").write_text(json.dumps(out, indent=2))
    print("\nwrote scoring/coevolution.json")


if __name__ == "__main__":
    main()
