# Aegis — Build Roadmap

Honest status: Aegis is past proof-of-concept (a real environment with three
vulnerability classes, a unified benchmark/leaderboard, a continuous
policy-gradient learner, and verified research results) but not yet a
large-scale hosted platform. This roadmap is the path from here to a benchmark
labs adopt and a dataset that compounds. Effort estimates assume one focused
engineer.

## M0 — Foundation (DONE)

- Verifiable environment: Scenario / `IDefense` / execution-derived `Reward`.
- Scenario 01 (reentrancy): vulnerable target, fast + patient attackers.
- Defenses: rate-limit (per-block & windowed) and a behavioral per-address invariant.
- Single-agent learning (discovers the optimal cap from reward alone).
- Co-evolution arms race; two results: (i) single-attacker training overfits
  (worst-case 0.00) vs co-evolution (0.50); (ii) a behavioral defense crosses the
  rate-limiting floor (1.00, zero false positives).
- CI, Makefile, contributor + scenario-authoring guides, paper draft.

## M1 — Scenario library (in progress)

FOUR structurally different vulnerability classes are DONE, each reproducing
the overfit-vs-generalize result, which is what proves the *methodology* (not a
quirk of one bug) is what's being measured:

- Scenario 01 — reentrancy (rate threshold vs per-address invariant / reentrancy lock).
- Scenario 02 — oracle/price manipulation (fixed anchor vs lagged oracle).
- Scenario 03 — broken access control (value/rate cap vs authorization invariant).
- Scenario 04 — flash-loan governance takeover (vote-count cap vs snapshot invariant).

All four are wired into a single declarative registry, so the unified
leaderboard, generalization study, and arms race pick them up automatically
(`python3 -m aegis bench`). Remaining — the biggest credibility jump is more,
and *forked-mainnet*, classes:

- ERC4626 share-inflation / first-depositor donation (local; rounding/economic).
- Flash-loan price manipulation (forked mainnet; pinned block; real DEX pair).
- Honeypot / canary tripwire (local; first touch trips the breaker).
- Dependency: an archive RPC (Alchemy/Infura) and a `forking` profile.

## M2 — Real RL training stack (in progress)

Make "learning" robust, not a bandit over a grid.

- **Continuous / multi-parameter defense parameterization** (DONE):
  `aegis.env.RobustRateLimitEnv` exposes a continuous `(window, cap)` action over
  a Gymnasium-style `reset()/step()` API.
- **A policy-gradient optimizer** (DONE): `aegis.agents.GaussianREINFORCE`
  (diagonal-Gaussian REINFORCE with a moving-average baseline, pure Python). It
  optimizes worst-case reward over the whole attacker grid and beats the
  hand-picked grid; `python3 -m aegis train`.
- **Train/test generalization split** (DONE): trains each defense family on a
  train attacker set and reports worst-case on a held-out test set. Result:
  structural defenses generalize (gap 0.00), threshold/rate defenses overfit
  (gap 1.00), in all three scenarios.
- Remaining: a vectorized scorer (a pool of `anvil` instances / parallel `forge`)
  for throughput, and PPO/CEM baselines for richer action spaces.

## M3 — Behavioral defenses + adversarial co-evolution (≈3–4 weeks)

- Cross-transaction address reputation, graph/flow features, learned classifiers.
- Co-evolve harder attackers against them (Sybil across addresses, cross-block
  laundering) — all in simulation.

## M4 — Hosted leaderboard + trajectory dataset (≈4–6 weeks)

The compounding-moat layer.

- Cloudflare Workers + D1 (+ R2) service: submit a defense (or attacker), score it
  in a sandbox, rank it.
- **Sandboxed runner** for untrusted Solidity — the hard, security-sensitive part
  (isolation, resource limits, no network).
- Capture every submission's attack/defense trajectory: the dataset asset.

## M5 — Packaging & standardization (in progress)

- **`aegis` Python package** (DONE): installable `aegis-gym` (pyproject) exposing
  an `aegis` console script and a `reset()/step()` env; forge-free unit tests in
  CI. Remaining: publish to PyPI.
- A Foundry scenario template + versioned, frozen benchmark releases (the
  SWE-bench model) so scores are comparable over time.
- Reproducibility harness; submit the paper to a security/ML workshop.

## Definition of "investment / paper ready"

- ≥3 scenarios including ≥1 forked-mainnet class (M1).
- A train/test generalization result, not just in-sample (M2).
- A behavioral-vs-adaptive co-evolution result (M3).
- A live leaderboard with external submissions and captured trajectories (M4).

## Next two weeks (concrete sprint)

1. M1: land the flash-loan forked-mainnet scenario end-to-end (target, attack,
   benign, scorer, baseline test).
2. M2 (start): vectorize the scorer with an `anvil` pool; add the train/test
   attacker split to `coevolve.py`.
3. Publish the repo with CI green and the paper draft as `docs/PAPER.md`.
