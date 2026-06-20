"""Active learning over the ~10^10 configuration space.

Random sampling wastes EVM calls on points whose outcome the model already knows.
Active learning instead scores the points the model is most UNCERTAIN about —
the decision boundaries and composition interactions — extracting more
information per (expensive) EVM execution.

Two entry points:
  * ``simulate`` — a pool-based active-learning experiment on the EXISTING
    labeled corpus (labels revealed only when queried). It compares uncertainty
    sampling against random sampling and shows active reaches higher accuracy per
    label. No EVM calls; fast and reproducible.
  * ``acquire`` — the real loop: train on the corpus, propose fresh candidate
    configurations from the combinatorial space, and score only the most
    uncertain ones on the EVM, appending them to the dataset.
"""
from __future__ import annotations

import random

from . import classify, sweep
from .sweep import _is_structural, _spaces


# --------------------------------------------------------------------------- #
# Pool-based active-learning simulation (no EVM)
# --------------------------------------------------------------------------- #
def _uncertainty(model, x) -> float:
    # distance from the decision boundary; smaller = more uncertain
    return abs(model.predict_proba(x) - 0.5)


def _al_curve(strategy: str, records, test_idx, seed, rounds, batch, seed_size, train_fn=None):
    train_fn = train_fn or classify.train
    rng = random.Random(seed)
    n = len(records)
    pool = [i for i in range(n) if i not in test_idx]
    rng.shuffle(pool)
    labeled = pool[:seed_size]
    unlabeled = pool[seed_size:]

    X = [classify.featurize(r) for r in records]
    y = [classify.label(r) for r in records]
    Xte = [X[i] for i in test_idx]
    yte = [y[i] for i in test_idx]

    crng = random.Random(seed + 99)
    curve = []
    for _ in range(rounds):
        model = train_fn([X[i] for i in labeled], [y[i] for i in labeled], seed=seed)
        acc = classify.evaluate(model, Xte, yte)["accuracy"]
        curve.append((len(labeled), acc))
        if not unlabeled:
            break
        if strategy == "committee":
            # query-by-committee: disagreement across bootstrap-trained models
            committee = []
            lab = labeled
            for c in range(5):
                boot = [lab[crng.randrange(len(lab))] for _ in range(len(lab))]
                committee.append(train_fn([X[i] for i in boot], [y[i] for i in boot], seed=seed + c))
            def _disagree(i):
                ps = [m.predict_proba(X[i]) for m in committee]
                mean = sum(ps) / len(ps)
                return -sum((p - mean) ** 2 for p in ps)  # higher variance first
            unlabeled.sort(key=_disagree)
            pick = unlabeled[:batch]
        elif strategy == "active":
            unlabeled.sort(key=lambda i: _uncertainty(model, X[i]))  # most uncertain first
            pick = unlabeled[:batch]
        else:
            pick = unlabeled[:batch]  # already shuffled => random
        labeled += pick
        unlabeled = [i for i in unlabeled if i not in set(pick)]
    return curve


def _trainer(model: str):
    if model == "mlp":
        from . import mlp

        return mlp.train
    return classify.train


def simulate(rounds: int = 9, batch: int = 12, seed_size: int = 12, seed: int = 0,
             n_seeds: int = 8, scenario: str | None = None, model: str = "logreg"):
    """Average the active-vs-random curves over several seeds to de-noise the
    small-sample variance of the classifier. Honest: reports whatever the data
    shows, including the regime where active learning helps and where it doesn't.
    Pass `scenario` to restrict to one class (e.g. the hard 'behavioral' one) and
    `model` to choose the learner ('logreg' or nonlinear 'mlp')."""
    records = sweep.read()
    if scenario:
        records = [r for r in records if r["scenario"] == scenario]
    if len(records) < 100:
        raise RuntimeError(
            f"dataset too small ({len(records)}). Generate it: python3 -m aegis dataset --budget 400"
        )

    train_fn = _trainer(model)
    arms = {"uncertainty": [], "committee": [], "random": []}
    strat = {"uncertainty": "active", "committee": "committee", "random": "random"}
    for s in range(seed, seed + n_seeds):
        rng = random.Random(s)
        idx = list(range(len(records)))
        rng.shuffle(idx)
        test_idx = set(idx[: len(records) // 4])  # 25% held out, shared by all arms
        for name, st in strat.items():
            arms[name].append(_al_curve(st, records, test_idx, s, rounds, batch, seed_size, train_fn))

    def _avg(runs):
        m = min(len(r) for r in runs)
        return [(runs[0][j][0], sum(r[j][1] for r in runs) / len(runs)) for j in range(m)]

    return {
        "curves": {name: _avg(runs) for name, runs in arms.items()},
        "n_total": len(records),
        "n_test": len(records) // 4,
        "n_seeds": n_seeds,
    }


# --------------------------------------------------------------------------- #
# Real acquisition loop (scores uncertain points on the EVM)
# --------------------------------------------------------------------------- #
def _candidate(rng) -> dict:
    """Sample one un-scored candidate configuration from the space."""
    space = rng.choice(_spaces())
    fam = rng.choice(space.families)
    attacker = rng.choice(space.attackers)
    params = fam["sample"](rng)
    return {
        "space": space,
        "family": fam,
        "attacker": attacker,
        "params": params,
        "scenario": space.scenario,
        "structural": fam["structural"] or _is_structural(params),
    }


def acquire(budget: int = 40, pool: int = 400, seed: int = 0, on_progress=None) -> int:
    """Train on the corpus, propose `pool` candidates, score the `budget` most
    uncertain on the EVM, and append them. Returns the number added."""
    records = sweep.read()
    if len(records) < 50:
        raise RuntimeError("dataset too small; run `aegis dataset` first")
    model = classify.train(
        [classify.featurize(r) for r in records], [classify.label(r) for r in records], seed=seed
    )

    rng = random.Random(seed)
    seen = sweep._existing_keys()
    cands = []
    while len(cands) < pool:
        c = _candidate(rng)
        import json

        key = json.dumps([c["scenario"], c["params"], c["attacker"], c["family"]["name"]], sort_keys=True)
        if key in seen:
            continue
        seen.add(key)
        feat = classify.featurize(
            {"scenario": c["scenario"], "structural": c["structural"], "params": c["params"],
             "attacker": c["attacker"], "reward": 0}
        )
        c["uncertainty"] = _uncertainty(model, feat)
        cands.append(c)

    cands.sort(key=lambda c: c["uncertainty"])  # most uncertain first
    added = 0
    for c in cands[:budget]:
        s = c["space"]
        env = {**s.static_env, **c["params"], s.attacker_knob: c["attacker"]}
        try:
            d = sweep.foundry.run_test(s.match_test, s.json_file, env)
        except RuntimeError:
            continue
        import json
        from datetime import datetime, timezone

        rec = {
            "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "scenario": c["scenario"],
            "family": c["family"]["name"],
            "structural": c["structural"],
            "params": c["params"],
            "attacker": c["attacker"],
            "saved": round(d["saved_frac_1e18"] / 1e18, 4),
            "fp": int(d["fp"]),
            "reward": round(d["reward_1e18"] / 1e18, 4),
            "acquired": "active",
        }
        with sweep.CORPUS.open("a") as fh:
            fh.write(json.dumps(rec) + "\n")
        added += 1
        if on_progress:
            on_progress(added, budget)
    return added
