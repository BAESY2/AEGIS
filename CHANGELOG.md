# Changelog

All notable changes to Aegis. The benchmark task itself is versioned separately
in [BENCHMARK.md](./BENCHMARK.md) so scores stay comparable over time.

## [0.4] — submission loop, real-data Chainlink class, hosted backend

### Added
- **Defense submission harness**: drop a defense into `submissions/Submission.sol`
  and `aegis submit` (or `make submit`) scores it across a scenario's attacker
  grid and reports your worst-case reward and leaderboard rank — no registry edits.
- **GitHub-native submission**: `.github/workflows/submission.yml` auto-scores a
  `submissions/` PR and comments the rank.
- **ForkChainlink** real-data class: `ChainlinkReferenceGuard` blocks when a
  manipulable spot diverges from an **independent** trusted oracle. The fork test
  reads the live Chainlink ETH/USD feed and Uniswap spot, executes a real swap to
  crash the spot, and shows the guard blocks the manipulated price.
- **Hosted-leaderboard backend scaffold** (`server/app.py`, stdlib only):
  `/health`, `/leaderboard`, `/submissions`, `/score`; submitted-code execution
  is disabled by default and gated behind a sandbox flag.

## [0.3] — combinatorial space, a no-free-lunch class, forked-mainnet, honest analyses

### Added
- **Scenario 05 — no-free-lunch frontier**: a stolen-key drain where the
  authorization invariant is useless and no defense reaches perfect recall at
  zero false positives.
- **Forked-mainnet**: `ForkOracle` (live Uniswap V2 reserves + computed
  manipulation) and `ForkSwap` (executes a real swap on the live pool, moving the
  on-chain price). Both skip without an RPC.
- **Composition** (`CompositeDefense`) as a first-class primitive (2^N stacks) and
  `aegis space` quantifying the configuration space at ~1.1 × 10^10 matchups.
- **Analyses** (each with an honest result): `aegis transfer` (cross-class gap
  +17%), `aegis robust` (minimax + regret), `aegis pareto` (frontier), `aegis
  explore` (active learning, honestly reported as a marginal lever), and an MLP
  learner option.
- Dataset grown to 2,300+ EVM-verified labels; paper Addendum II; README
  at-a-glance index.

## [0.2] — four-class benchmark, unified CLI, RL stack, dataset

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
