# From a hand-carved engine to a factory — the scaling blueprint

An honest answer to "pure Python (no torch/numpy) is a portfolio flex, not a
production AI factory." Correct. This document is the architecture that turns the
mechanism proof into the product, and what each phase actually needs.

## What the pure-Python core is — and is not

The zero-dependency Python (`aegis-gym/`) was a deliberate choice for the *current*
job: a **mechanism proof** that anyone can reproduce with `python3` and `forge`,
in CI, with no GPU and no install. That is exactly right for a benchmark and for
de-risking the science (the guards, the generalization result, the swarm/adaptive
co-evolution, the real-data training).

It is **not** a training factory. A real swarm — thousands of attacker/defender
agents learning in real time — needs frameworks and infrastructure. We do not
pretend otherwise, and we have not faked a `torch` import to look the part.

## The three things the factory needs (and why)

1. **A fast, vectorized environment.** The pure-Python constant-product sim runs
   one episode at a time. Production training needs millions of steps/sec: a
   vectorized env (batched on GPU) or a compiled AMM/EVM simulator (Rust/Go, or
   `revm`) so thousands of agents train in parallel. The current `dex.py`/`env.py`
   are the *reference semantics* the fast env must match.
2. **A real learning stack.** PyTorch policies (the defender as a network mapping
   live pool/traffic features → action), trained with population/league methods
   on **Ray/RLlib** (or PufferLib) across a GPU cluster. The current
   evolutionary co-evolution (`arena.py`) is the *algorithm prototype*; it becomes
   gradient-based, networked policies at scale.
3. **A real-time inference path.** The trained policy served as a low-latency
   **keeper** that watches mainnet (state + mempool), scores manipulation risk
   sub-block, and trips the on-chain `CircuitBreaker` (`src/CircuitBreaker.sol`,
   already built and installable) before a malicious borrow/liquidation lands.

## The data flywheel (this is the moat, not the code)

Every protocol Aegis Sentinel monitors contributes a live oracle/telemetry
stream. That data — proprietary, never open-sourced (see `LICENSING.md`) — is the
training set that a fork cannot reconstruct: more clients → more data → better
policies → better detection → more clients. The open code is the funnel; the
**operated service + the compounding dataset** is the factory's fuel.

## Phased plan (what each phase costs)

| Phase | What | Needs |
|-------|------|-------|
| **0 — now (done)** | mechanism proofs (pure Python), reference guards, fork-validated detection, the on-chain `CircuitBreaker`, the Sentinel monitor MVP on live mainnet | a laptop |
| **1 — MVP product** | vectorized env + PyTorch league training (single GPU); production keeper (mempool watch + auto-trip); 1–3 paying pilots monitored | 1 GPU box, infra eng, seed capital |
| **2 — the factory** | Ray cluster; thousands of agents; **continuous** learning from live client telemetry; multi-chain keepers | GPU cluster, SRE, the raise |

## Why fund this now

Phase 0 — the part that is genuinely hard to get *right* (does the defense
generalize? do the guards hold on real data? does a learned policy beat a fixed
one?) — is **done and verifiable in this repo**, on real mainnet data. That
de-risks the science. The raise does not pay to discover whether it works; it pays
to **industrialize a proven mechanism** (Phase 1→2) and to capture the data
flywheel before a competitor does. The hand-carved engine proves the design; the
capital builds the factory.
