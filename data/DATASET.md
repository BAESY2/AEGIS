# Aegis trajectory dataset

An EVM-verified, label-free corpus of smart-contract defense matchups. Every record is produced by contract execution on a forked chain (Foundry) — no human labels, no Python heuristics. This is the concrete form of the project's data asset: each scenario added and each match played enlarges it.

- **Records:** 1030
- **Positive-reward (precise) matchups:** 654
- **Zero/negative-reward matchups:** 376
- **Provenance:** deterministic; regenerate/extend with `cd aegis-gym && python3 -m aegis dataset --budget N --seed S`.

## Per-scenario coverage

| Scenario | Records | Families (n) |
|----------|:-------:|--------------|
| access | 231 | *identity (10), rate-based (221) |
| governance | 86 | *snapshot (9), vote-cap (77) |
| oracle | 497 | fixed-anchor (245), *lagged-oracle (252) |
| reentrancy | 216 | *behavioral (20), rate-based (196) |

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

License: MIT (same as the repository).
