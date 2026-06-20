"""Cross-scenario transfer: does 'will this defense hold?' generalize across
vulnerability CLASSES (not just across attackers within a class)?

Leave-one-class-out: train the defense-outcome classifier on every class except
one, test on the held-out class, and compare to a within-class baseline (train
and test on the held-out class itself). A large gap means defense-quality
structure is class-specific — you cannot predict a governance defense from
reentrancy data — which is the quantitative case for benchmark BREADTH: each new
vulnerability class carries information the others don't.
"""
from __future__ import annotations

from . import classify, sweep


def run(seed: int = 0) -> dict:
    records = sweep.read()
    by_class: dict[str, list] = {}
    for r in records:
        by_class.setdefault(r["scenario"], []).append(r)

    rows = []
    for held, recs in sorted(by_class.items()):
        if len(recs) < 20:
            continue
        # cross-class: train on all OTHER classes, test on the held-out class
        train = [r for r in records if r["scenario"] != held]
        model = classify.train(
            [classify.featurize(r) for r in train], [classify.label(r) for r in train], seed=seed
        )
        cross = classify.evaluate(
            model, [classify.featurize(r) for r in recs], [classify.label(r) for r in recs]
        )["accuracy"]

        # within-class baseline: 75/25 split inside the held-out class
        import random

        rng = random.Random(seed)
        order = recs[:]
        rng.shuffle(order)
        cut = max(5, int(len(order) * 0.75))
        wm = classify.train(
            [classify.featurize(r) for r in order[:cut]],
            [classify.label(r) for r in order[:cut]],
            seed=seed,
        )
        within = classify.evaluate(
            wm,
            [classify.featurize(r) for r in order[cut:]],
            [classify.label(r) for r in order[cut:]],
        )["accuracy"]

        base_rate = sum(classify.label(r) for r in recs) / len(recs)
        rows.append(
            {
                "held_out": held,
                "n": len(recs),
                "base_rate": base_rate,
                "cross_class_acc": cross,
                "within_class_acc": within,
                "transfer_gap": within - cross,
            }
        )
    return {"rows": rows}
