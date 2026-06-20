# Aegis Benchmark — frozen spec v0.2

A benchmark is only useful if scores are comparable over time. This file pins
the **v0.2** task definition: the scenarios, attacker grids, benign suites,
metric, and train/test split. Treat it like a dataset release (the SWE-bench
model) — changing any of it means cutting a new version, not editing v0.2.

Regenerate the current results into [LEADERBOARD.md](./LEADERBOARD.md) with
`cd aegis-gym && python3 -m aegis bench`, and gate them in CI with
`python3 -m aegis verify`.

## Metric

For a defense configuration `θ` and an attacker `a`, both are executed on the
EVM (Foundry):

```
reward(θ, a) = funds_saved(θ, a) − false_positive_rate(θ)      ∈ [−1, 1]
```

A submission is ranked by **worst-case reward** over the scenario's full
attacker grid — `min_a reward(θ, a)` — because a production defense is only as
good as its worst day against any attacker in the family. The reward penalizes
false positives 1:1, so blocking everything nets ~0.

## Scenarios (v0.2)

| # | Key | Attacker knob | Attacker grid | Benign suite | Horizon |
|---|-----|---------------|---------------|--------------|:-------:|
| 01 | `reentrancy` | `AEGIS_TAKE` (drain rate, eth/block) | {2, 3, 4, 5, 7, 11} | 3 retail + 1 whale (4) | 12 |
| 02 | `oracle` | `AEGIS_PUMP` (spot pump, eth) | {2, 3, 5, 10, 100} | 1 fair + 1 organic-drift borrow | — |
| 03 | `access` | `AEGIS_TAKE` (drain rate, eth/block) | {2, 3, 4, 5, 7, 11} | 3 admin ops + 1 whale (4) | 12 |
| 04 | `governance` | `AEGIS_TAKE` (flash-borrowed votes) | {100, 150, 300, 1000, 5000} | 2 genuinely-held voters | — |

Each scenario ships a vulnerable target, a parameterized exploit, a benign suite
(including an adversarial-looking-but-legitimate "whale"), and ≥1 threshold
family + ≥1 structural family. See `aegis-gym/aegis/registry.py` for the exact
defense configurations.

## Train / test split (generalization)

The attacker grid is split into the **stronger** half (train) and the **weaker**
half (test); a defense family is selected by best-response (max worst-case
reward) on train, then frozen and evaluated on the held-out test attackers. The
gap `train − test` measures overfitting.

| Scenario | Train attackers | Test attackers |
|----------|-----------------|----------------|
| 01 reentrancy | {5, 7, 11} | {2, 3, 4} |
| 02 oracle | {5, 10, 100} | {2, 3} |
| 03 access | {5, 7, 11} | {2, 3, 4} |
| 04 governance | {300, 1000, 5000} | {100, 150} |

## Invariants asserted by `aegis verify`

For every scenario in v0.2:

1. The top-ranked defense (by worst-case reward) is **structural**.
2. Every structural family **generalizes**: train/test gap ≈ 0.
3. Every threshold/rate family **overfits**: train/test gap is large (≥ 0.5).

These hold across all four vulnerability classes and are gated in CI.

## Reference results (v0.2)

The frozen result is "structural defenses generalize (gap 0.00); threshold/rate
defenses overfit (gap 1.00), in every class." Exact per-defense rankings are in
[LEADERBOARD.md](./LEADERBOARD.md) and `scoring/leaderboard.json`.

## Versioning

- **v0.2** — four classes (reentrancy, oracle, access, governance); unified
  registry; continuous policy-gradient learner.
- A future **v0.3** may add forked-mainnet classes and additional attacker
  parameterizations; it will be a new frozen spec so v0.2 scores stay comparable.
