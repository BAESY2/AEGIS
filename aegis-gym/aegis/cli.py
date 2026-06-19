"""`aegis` command-line interface — one entry point for the whole benchmark.

    python3 -m aegis list                 # show registered scenarios
    python3 -m aegis bench                 # full leaderboard + generalization -> JSON + LEADERBOARD.md
    python3 -m aegis leaderboard [key]     # print the ranking for one/all scenarios
    python3 -m aegis generalize [key]      # train/test generalization study
    python3 -m aegis coevolve [key]        # attacker/defender arms race
    python3 -m aegis score <key> <cfg> <atk>   # score one matchup on the EVM
"""
from __future__ import annotations

import argparse
import sys

from . import analysis, registry, report


def _print_leaderboard(scenario, cache):
    rows = analysis.leaderboard(scenario, cache)
    print(f"\nScenario {scenario.id} — {scenario.title}")
    print(f"  {'defense':<42}{'family':<14}{'wc-saved':>9}{'wc-reward':>10}{'fp':>6}")
    print("  " + "-" * 80)
    for r in rows:
        tag = "*" if r.structural else " "
        print(
            f"  {tag}{r.label:<41}{r.family:<14}{r.worst_case_saved:>9.2f}"
            f"{r.worst_case_reward:>10.2f}{r.fp:>4}/{r.benign_total}"
        )
    print("  (* = structural / invariant-based defense)")


def _print_generalization(scenario, cache):
    rows, train, test = analysis.generalization(scenario, cache)
    print(f"\nScenario {scenario.id} — {scenario.title}")
    print(f"  train attackers={train}  test attackers={test}")
    print(f"  {'family':<16}{'trained config':<42}{'train':>7}{'test':>7}{'gap':>7}")
    print("  " + "-" * 78)
    for r in rows:
        print(f"  {r.family:<16}{r.trained_label:<42}{r.train:>7.2f}{r.test:>7.2f}{r.gap:>7.2f}")


def _print_coevolution(scenario, cache):
    # arms race on the first non-structural (threshold) family.
    family_name = next(
        (n for n, fam in scenario.families.items() if not fam[0].structural),
        next(iter(scenario.families)),
    )
    res = analysis.coevolve(scenario, family_name, cache)
    print(f"\nScenario {scenario.id} — {scenario.title}  (family: {family_name})")
    for step in res["history"]:
        tail = (
            "  -> no new evasion. equilibrium."
            if step.attacker_escalation in step.population
            else f"  attacker escalates to {scenario.attacker_knob}={step.attacker_escalation}"
        )
        print(
            f"  round {step.round}: pop={step.population} -> {step.defender_label} "
            f"(worst-case reward {step.worst_case_reward:+.2f}){tail}"
        )
    print(
        f"  naive (tuned on strongest only): {res['naive'].label} "
        f"-> worst-case saved {res['naive_worstcase_saved']:.2f}"
    )
    print(
        f"  co-evolved:                      {res['coevolved'].label} "
        f"-> worst-case saved {res['coevolved_worstcase_saved']:.2f}"
    )


def _scenarios(key: str | None):
    if key in (None, "all"):
        return registry.all_scenarios()
    return [registry.get(key)]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="aegis", description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list", help="list registered scenarios")
    sub.add_parser("bench", help="full leaderboard + generalization -> JSON + LEADERBOARD.md")
    for name in ("leaderboard", "generalize", "coevolve"):
        p = sub.add_parser(name)
        p.add_argument("scenario", nargs="?", default="all")

    ps = sub.add_parser("score", help="score one matchup on the EVM")
    ps.add_argument("scenario")
    ps.add_argument("config_label", help="substring matching a defense label")
    ps.add_argument("attacker", type=int)

    args = parser.parse_args(argv)
    cache = analysis.ScoreCache()

    if args.cmd == "list":
        for sc in registry.all_scenarios():
            fams = ", ".join(sc.families)
            print(f"  {sc.id} {sc.key:<14} {sc.title}")
            print(f"       families: {fams}")
            print(f"       attackers ({sc.attacker_knob}): {sc.attacker_grid}")
        return 0

    if args.cmd == "bench":
        print("running full benchmark on the EVM (this invokes forge per matchup) ...")
        rep = report.build_full_report(cache)
        jp = report.write_json(rep)
        mp = report.write_markdown(rep)
        for sc in registry.all_scenarios():
            _print_leaderboard(sc, cache)
            _print_generalization(sc, cache)
        print(f"\nwrote {jp.relative_to(report.ROOT)} and {mp.relative_to(report.ROOT)}")
        return 0

    if args.cmd == "leaderboard":
        for sc in _scenarios(args.scenario):
            _print_leaderboard(sc, cache)
        return 0

    if args.cmd == "generalize":
        for sc in _scenarios(args.scenario):
            _print_generalization(sc, cache)
        return 0

    if args.cmd == "coevolve":
        for sc in _scenarios(args.scenario):
            _print_coevolution(sc, cache)
        return 0

    if args.cmd == "score":
        sc = registry.get(args.scenario)
        configs = analysis.configs_of(sc)
        matches = [c for c in configs if args.config_label.lower() in c.label.lower()]
        if not matches:
            print(f"no config matching '{args.config_label}'. options:", file=sys.stderr)
            for c in configs:
                print(f"  {c.label}", file=sys.stderr)
            return 2
        cfg = matches[0]
        res = sc.score(cfg, args.attacker)
        print(f"scenario={sc.key} defense='{cfg.label}' {sc.attacker_knob}={args.attacker}")
        print(f"  saved={res.saved:.2f}  fp={res.fp}/{res.benign_total}  reward={res.reward:+.2f}")
        return 0

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
