# Learning a defense from verifiable reward

Aegis treats defense as a learning problem: the EVM hands back a scalar reward
for any candidate defense, with no human labels, so an agent can optimize it
directly. This document describes the environment and the reference agent.

## The reward

For a fixed scenario, a defense configuration `θ` is scored against an attacker
`a` by executing both the exploit and a legitimate-traffic suite on a forked
chain:

```
reward(θ, a) = funds_saved(θ, a) − false_positive_rate(θ)        ∈ [−1, 1]
```

The false-positive term is what makes the problem non-trivial: blocking
everything earns the funds-saved term but pays the full penalty, netting zero.
Positive reward requires *precision*.

## The environment (`aegis.env`)

`RobustRateLimitEnv` follows the Gymnasium `reset()` / `step(action)` contract
(without importing gymnasium — the core stays dependency-free).

- **Action** — a *continuous* circuit-breaker configuration `(window, cap)`,
  rounded to the integer grid the on-chain `WindowedRateLimitDefense` accepts.
- **Reward** — the **worst-case** reward over the *entire* attacker grid:

  ```
  R(θ) = min_a  reward(θ, a)
  ```

  Optimizing the worst case (not the average) is the production-relevant
  objective: a defense is only as good as its worst day against any attacker in
  the family. This is also why a defense that beats one attacker can still score
  poorly — it must be precise against all of them at once.
- **Episode** — a single step (a black-box / contextual-bandit setting): the
  agent picks a global configuration rather than reacting to a per-timestep
  state. `reset()` returns a constant observation.

Every `step` is decided by contract execution; results are memoized per
`(scenario, config, attacker)` so repeated evaluations of the same rounded
configuration are free.

## The agent (`aegis.agents.GaussianREINFORCE`)

A policy-gradient agent over a diagonal Gaussian policy `N(μ, σ)` on the action:

```
sample   a ~ N(μ, σ),  clipped to the action box
update   μ ← μ + lr · (R − b) · (a − μ) / σ²            (score-function gradient)
```

with a moving-average baseline `b` for variance reduction and an annealed `σ`
(explore early, exploit late). The math is explicit and the action is a short
tuple, so there is no numpy/torch dependency.

The deliverable policy is the best configuration the agent validated on-chain
(the incumbent, as in evolutionary / black-box optimization); the final policy
mean `μ` is reported alongside it for transparency.

## What it finds

Run `python3 -m aegis train reentrancy`. From the verifiable reward alone:

- continuous search **beats the hand-picked grid** (whose best worst-case reward
  is 0.25), typically converging on a tight breaker (`cap` = one chunk) at
  worst-case reward **0.75**;
- it never reaches **1.0**, because any rate cap that stops the patient drain
  also blocks the legitimate whale (a false positive);
- switching to the **structural** family (the per-address invariant) reaches
  reward 1.0 with zero false positives.

So the learner independently arrives at the benchmark's central conclusion:
**structure beats thresholds.** The contribution is the environment and the
verifiable signal; the optimizer is deliberately simple, and richer ones
(PPO/CEM, multi-parameter and learned-classifier defenses) are future work.

## Extending

- A new scenario added to `aegis/registry.py` is immediately trainable: point an
  env at its key, or generalize the action space to the scenario's defense
  family.
- For throughput on larger sweeps, the per-matchup `forge` call is the bottleneck
  — a pool of `anvil` instances / parallel `forge` is the planned vectorization
  (see `docs/ROADMAP.md`).
