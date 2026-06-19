# Aegis — Build Roadmap

Honest status: Aegis is past proof-of-concept (a real environment with two
verified research results) but not yet a large-scale platform. This roadmap is
the path from here to a benchmark labs adopt and a dataset that compounds. Effort
estimates assume one focused engineer.

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

Scenario 02 (oracle/price manipulation, local mock AMM) is DONE: a second,
structurally different vulnerability class that reproduces the floor-and-crossing
result, proving the framework generalizes. Remaining:

The single biggest credibility jump: more, and *forked-mainnet*, vulnerability
classes so results are not reentrancy-specific.

- Flash-loan price manipulation (forked mainnet; pinned block; real DEX pair).
- Oracle manipulation (spot vs TWAP).
- Governance takeover.
- Honeypot / canary tripwire (local; first touch trips the breaker).
- Dependency: an archive RPC (Alchemy/Infura) and a `forking` profile.

## M2 — Real RL training stack (≈3–5 weeks)

Make "learning" robust, not a bandit over a grid.

- Continuous / multi-parameter defense parameterization.
- A proper optimizer (PPO/REINFORCE or CEM) with a vectorized scorer (a pool of
  `anvil` instances / parallel `forge`) for throughput.
- **Train/test generalization split** (DONE): `aegis-gym/generalize.py` trains
  each defense family on a train attacker set and reports worst-case on a held-out
  test set. Result: structural defenses generalize (gap 0.00), threshold/rate
  defenses overfit (gap 1.00), in both scenarios. Remaining: continuous-param
  policy-gradient and a vectorized (anvil-pool) scorer for throughput.

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

## M5 — Packaging & standardization (≈2–3 weeks)

- `aegis` Python package exposing a clean `reset()/step()` gym API on PyPI.
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
