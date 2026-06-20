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
    sub.add_parser("verify", help="assert the benchmark invariants on the EVM (CI gate)")
    sub.add_parser("trajectories", help="summarize the compounding trajectory ledger")
    for name in ("leaderboard", "generalize", "coevolve"):
        p = sub.add_parser(name)
        p.add_argument("scenario", nargs="?", default="all")

    ps = sub.add_parser("score", help="score one matchup on the EVM")
    ps.add_argument("scenario")
    ps.add_argument("config_label", help="substring matching a defense label")
    ps.add_argument("attacker", type=int)

    pt = sub.add_parser("train", help="policy-gradient agent learns a robust defense")
    pt.add_argument("scenario", nargs="?", default="reentrancy")
    pt.add_argument("--episodes", type=int, default=60)
    pt.add_argument("--seed", type=int, default=0)

    pd = sub.add_parser("dataset", help="generate/extend the EVM-verified trajectory corpus")
    pd.add_argument("--budget", type=int, default=200, help="number of NEW distinct matchups to add")
    pd.add_argument("--seed", type=int, default=0)

    pc = sub.add_parser("classify", help="train a defense-outcome classifier on the dataset")
    pc.add_argument("--seed", type=int, default=0)
    pc.add_argument("--test-frac", type=float, default=0.25)

    pr = sub.add_parser("recommend", help="recommend the defense to deploy for a scenario")
    pr.add_argument("scenario")

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
        sp = report.write_generalization_svg(rep)
        for sc in registry.all_scenarios():
            _print_leaderboard(sc, cache)
            _print_generalization(sc, cache)
        print(
            f"\nwrote {jp.relative_to(report.ROOT)}, {mp.relative_to(report.ROOT)}, "
            f"and {sp.relative_to(report.ROOT)}"
        )
        return 0

    if args.cmd == "verify":
        ok = True
        for sc in registry.all_scenarios():
            rows = analysis.leaderboard(sc, cache)
            top = rows[0]
            if not top.structural:
                print(f"FAIL {sc.key}: top defense '{top.label}' is not structural")
                ok = False
            gen_rows, train, test = analysis.generalization(sc, cache)
            for r in gen_rows:
                if r.structural and abs(r.gap) > 0.01:
                    print(f"FAIL {sc.key}: structural family '{r.family}' did not generalize (gap {r.gap})")
                    ok = False
                if not r.structural and r.gap < 0.5:
                    print(f"FAIL {sc.key}: threshold family '{r.family}' did not overfit (gap {r.gap})")
                    ok = False
            if ok:
                print(f"OK   {sc.key}: structural defense '{top.label}' tops the board; "
                      f"structural generalizes, threshold overfits")
        print("\nbenchmark invariants:", "PASS" if ok else "FAIL")
        return 0 if ok else 1

    if args.cmd == "trajectories":
        from . import trajectory

        s = trajectory.summary()
        print(f"trajectory ledger: {s['total_matchups']} matchups recorded")
        if not s["scenarios"]:
            print("  (empty — run `aegis bench` or `aegis score` to accumulate trajectories)")
        for key, sc in s["scenarios"].items():
            print(f"\n  {key}: {sc['matchups']} matchups")
            for fam, f in sc["families"].items():
                tag = "*" if f["structural"] else " "
                rate = f["wins"] / f["n"] if f["n"] else 0.0
                print(f"   {tag}{fam:<14} n={f['n']:<4} positive-reward rate={rate:.0%}")
        print("\n(ledger: scoring/trajectories.jsonl — the compounding dataset asset)")
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

    if args.cmd == "train":
        from . import learn

        learn.train(args.scenario, episodes=args.episodes, seed=args.seed)
        return 0

    if args.cmd == "dataset":
        from . import sweep

        print(f"generating up to {args.budget} new EVM-verified matchups (seed {args.seed}) ...")

        def _progress(done, total):
            if done % 25 == 0 or done == total:
                print(f"  {done}/{total} new records")

        added = sweep.sweep(budget=args.budget, seed=args.seed, on_progress=_progress)
        card = sweep.write_card()
        st = sweep.stats()
        print(f"added {added} records; corpus now {st['total']} total "
              f"({st['positive_reward']} precise / {st['negative_or_zero_reward']} not)")
        print(f"wrote {card.relative_to(sweep.ROOT)} and data/trajectories.jsonl")
        return 0

    if args.cmd == "classify":
        from . import classify

        r = classify.run(test_frac=args.test_frac, seed=args.seed)
        print(f"dataset: {r['n_total']} matchups  (train {r['n_train']} / test {r['n_test']})")
        print(
            f"  test accuracy {r['test']['accuracy']:.1%}  "
            f"(precision {r['test']['precision']:.1%}, recall {r['test']['recall']:.1%}; "
            f"base rate {r['test_base_rate']:.1%})"
        )
        print("  most predictive features (|weight|, standardized):")
        for name, w in r["weights"][:5]:
            print(f"    {name:<14} {w:+.2f}")
        print(
            "  -> trained only on EVM-verified outcomes, the model predicts whether "
            "a defense holds WITHOUT running the EVM, beating the base rate. It learns "
            "the outcome is driven by the defense parameters relative to the attacker "
            "(a rate cap holds only when tight enough). The bigger the dataset grows, "
            "the better this model gets — the compounding data asset, made tangible."
        )
        return 0

    if args.cmd == "recommend":
        sc = registry.get(args.scenario)
        rows = analysis.leaderboard(sc, cache)
        top = rows[0]
        best_threshold = next((r for r in rows if not r.structural), None)
        gen_rows, train, test = analysis.generalization(sc, cache)
        gen = next((g for g in gen_rows if g.family == top.family), None)

        print(f"Scenario {sc.id} — {sc.title}")
        print(f"\n  ✅ RECOMMENDED: {top.label}  [{top.family}]")
        print(
            f"     worst-case funds saved {top.worst_case_saved:.0%}, "
            f"false positives {top.fp}/{top.benign_total}, "
            f"worst-case reward {top.worst_case_reward:+.2f}"
        )
        if gen is not None:
            verdict = "generalizes to unseen attackers" if abs(gen.gap) < 1e-9 else "overfits"
            print(f"     train/test gap {gen.gap:+.2f} — {verdict}")
        if best_threshold is not None and best_threshold.label != top.label:
            print(
                f"\n  ✗ Best threshold/rate alternative: {best_threshold.label} — "
                f"worst-case saved {best_threshold.worst_case_saved:.0%}, "
                f"FP {best_threshold.fp}/{best_threshold.benign_total} "
                f"(does not dominate the structural defense)."
            )
        # optional: the trained model's confidence that the pick holds
        try:
            from . import classify, sweep

            if len(sweep.read()) >= 20:
                recs = sweep.read()
                model = classify.train(
                    [classify.featurize(r) for r in recs],
                    [classify.label(r) for r in recs],
                    seed=0,
                )
                cfg = next(c for c in analysis.configs_of(sc) if c.label == top.label)
                atk = max(sc.attacker_grid)
                feat = classify.featurize(
                    {"scenario": sc.key, "structural": cfg.structural,
                     "params": cfg.env, "attacker": atk, "reward": 0}
                )
                print(f"\n  model confidence this defense holds: {model.predict_proba(feat):.0%} "
                      f"(from {len(recs)} EVM-verified matchups)")
        except Exception:
            pass
        print("\n  Deploy it as a one-line firewall hook (see README / examples/).")
        return 0

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
