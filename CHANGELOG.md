# Changelog

All notable changes to Aegis. The benchmark task itself is versioned separately
in [BENCHMARK.md](./BENCHMARK.md) so scores stay comparable over time.

## [Unreleased]

### Added
- **Benchmark v0.2 — four vulnerability classes** under one declarative registry:
  reentrancy (01), oracle/price manipulation (02), broken access control (03),
  and flash-loan governance takeover (04). Each ships a vulnerable target, a
  parameterized exploit, a benign suite, a threshold family, and a structural
  family.
- **Unified `aegis` Python package and CLI**: `list`, `bench`, `verify`,
  `leaderboard`, `generalize`, `coevolve`, `train`, `score`, `trajectories`.
  Zero runtime dependencies (only `forge` is required).
- **Auto-generated outputs**: `LEADERBOARD.md` (worst-case ranking) and a
  data-driven results chart (`docs/assets/generalization.svg`).
- **Continuous RL stack**: a Gymnasium-style environment (`aegis.env`) and a
  pure-Python policy-gradient agent (`aegis.agents`, `aegis train`).
- **Structural defenses**: per-address per-tx balance invariant, reentrancy lock,
  lagged-oracle guard, authorization (owner-only) invariant, and snapshot vote
  guard.
- **Compounding trajectory ledger**: every scored matchup is appended to
  `scoring/trajectories.jsonl`; summarize with `aegis trajectories`.
- **Living-benchmark CI**: `aegis verify` gates the central invariants
  (structural tops every scenario and generalizes; threshold defenses overfit),
  plus a `leaderboard` workflow that scores each PR and posts the ranking as a
  comment.
- **Quality & adoption**: installable package (`pyproject.toml`), 16 forge-free
  unit tests, issue/PR templates, a defense template + walkthrough
  (`examples/`), an architecture diagram, a frozen spec (`BENCHMARK.md`), and
  `docs/RL.md`.

### Result
Across all four classes, structural (invariant-based) defenses generalize to
unseen attackers (train/test gap ≈ 0.00) while threshold/rate defenses overfit
(gap ≈ 1.00) — gated in CI.

## [0.1.0] — initial proof of concept
- Reentrancy scenario, verifiable EVM reward, an epsilon-greedy learning demo,
  and the attacker/defender co-evolution arms race.
