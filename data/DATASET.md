# Aegis trajectory dataset

An EVM-verified, label-free corpus of smart-contract defense matchups. Every record is produced by contract execution on a forked chain (Foundry) — no human labels, no Python heuristics. This is the concrete form of the project's data asset: each scenario added and each match played enlarges it.

- **Records:** 2301
- **Positive-reward (precise) matchups:** 1684
- **Zero/negative-reward matchups:** 617
- **Provenance:** deterministic; regenerate/extend with `cd aegis-gym && python3 -m aegis dataset --budget N --seed S`.

## Per-scenario coverage

| Scenario | Records | Families (n) |
|----------|:-------:|--------------|
| access | 332 | *identity (10), rate-based (322) |
| behavioral | 731 | amount (105), behavioral (105), newdest (21), none (21), composite (479) |
| governance | 90 | *snapshot (9), vote-cap (81) |
| oracle | 793 | fixed-anchor (385), *lagged-oracle (408) |
| reentrancy | 355 | *behavioral (20), rate-based (308), *composite (27) |

`*` = structural / invariant-based defense.

## Schema (one JSON object per line, `trajectories.jsonl`)

```json
{"ts": "...", "scenario": "reentrancy", "family": "rate-based",
 "structural": false, "params": {"AEGIS_DEF": "windowed", "AEGIS_WINDOW": 8, "AEGIS_CAP": 3},
 "attacker": 2, "saved": 0.7, "fp": 1, "reward": 0.45}
```

- `params` are the scenario-specific defense knobs (the features).
- `attacker` is the attacker-strength axis for the scenario.
- `saved` ∈ [0,1], `fp` is the false-positive count, `reward` ∈ [-1,1] (the EVM-derived label).

## Suggested tasks

- **Defense-outcome prediction:** features → `reward` (regression) or `reward > 0` (classification): "will this defense hold?"
- **Robust-config search:** learn the configuration maximizing worst-case reward over the attacker axis (what `aegis train` does online).
- **Generalization study:** train on a subset of attackers/scenarios, test on held-out ones (structural vs threshold).

## Baseline model (`aegis classify`)

A logistic-regression model trained on this corpus predicts whether a defense holds (reward > 0) **without running the EVM**:

- Test accuracy: **68.9%** (precision 83.1%, recall 71.8%; base rate 72.7%), on 576 held-out matchups.
- It sharpens as the corpus grows — the compounding data asset in action.

License: MIT (same as the repository).
