# Aegis — Design

## 1. Problem

On-chain defense has matured into real-time monitoring products, but the layer
*beneath* them is missing: a shared, runnable, execution-grounded environment in
which a defense can be **trained** and **objectively ranked**. Today every team
benchmarks privately against its own incidents. Aegis makes the environment a
public good and the reward reproducible.

The design target is the same property that makes coding and math the dominant
RL domains: **verifiable reward**. A smart-contract exploit is the cleanest
possible verifier — run it on a fork; either the invariant (funds safe) holds or
it does not.

## 2. Architecture

```
            ┌─────────────────────────── Scenario ───────────────────────────┐
            │  Target (vulnerable)   Attack (verified PoC)   Benign (legit)   │
            └───────────────────────────────┬────────────────────────────────┘
                                             │  firewall hook: authorize()
                                             ▼
   Defense (IDefense)  ──►  Scorer (Foundry)  ──►  Reward (1e18)  ──►  results.json
   submission                runs attack + benign     execution-derived    leaderboard
```

- **Target** exposes exactly one integration point — the `authorize` hook — at
  the top of each sensitive function. Everything else is left deliberately
  exploitable, so the *defense*, not the target, is what is measured.
- **Attack** is a self-contained exploit contract. Scenario 01 (reentrancy) runs
  fully local; scenarios 02–04 pin a mainnet fork block for realistic state.
- **Benign** is a suite of legitimate interactions used to measure collateral
  damage (false positives).
- **Scorer** is a Foundry test. It runs the attack and the benign suite on
  *isolated* deployments (so stateful defenses cannot leak window state between
  the two measurements), then computes the reward.

## 3. The defense interface

```solidity
function authorize(address caller, bytes4 selector, uint256 value, bytes ctx)
    returns (bool allow);
```

`authorize` may be stateful (a circuit breaker accumulates outflow; an anomaly
model updates running statistics). `ctx` is an ABI-encoded, per-scenario snapshot
— for reentrancy it carries the caller's recorded balance and the target's live
ETH balance. The contract reverts on `allow == false`; for a reentrant exploit
that revert propagates through the whole call tree and unwinds the drain.

## 4. The reward function

```
reward = W_BLOCK * blocked  -  W_FP * (fpCount / benignTotal)
W_BLOCK = W_FP = 1.0   =>   reward in [-1, +1]
```

Design intent:

| Strategy        | blocked | fpRate | reward | reading                       |
|-----------------|:-------:|:------:|:------:|-------------------------------|
| Do nothing      | 0       | 0      | 0      | attack succeeds, users fine   |
| Block everything| 1       | 1      | 0      | protocol bricked == no value  |
| Precise defense | 1       | 0      | **1**  | the only winning quadrant     |

The penalty term is what makes the benchmark honest: it forces the
precision/recall tradeoff that defeats naive defenses in production (a paused
protocol is itself an outage). Later versions add a gas-overhead term and a
*liveness floor* so a permanently-tripped breaker scores strictly below a
functioning, undefended protocol.

## 5. Two products, one environment

- **As a benchmark (static):** publish a defense, get a reproducible score and a
  rank. This is the credibility / standard-setting play (cf. SWE-bench, OSWorld).
- **As a gym (dynamic, implemented):** `aegis-gym/` wraps the scorer in a
  `step(cap)` loop. An agent proposes a defense parameter, the environment
  returns the execution-derived reward, the agent updates — no human labeling,
  because the fork verifies it. The reference agent (an epsilon-greedy bandit)
  converges to the optimal cap band [5, 10] in ~18 episodes, discovering a
  defense that stops the drain while passing a legitimate whale. The reward
  landscape is single-peaked by construction:

  | cap (eth) | attack blocked | false positives | reward |
  |:---------:|:--------------:|:---------------:|:------:|
  | 0         | yes            | 4/4             | 0.00   |
  | 1, 3      | yes            | 1/4 (whale)     | 0.75   |
  | 5 – 10    | yes            | 0/4             | **1.00** |
  | 11+       | no             | 0/4             | 0.00   |

The same scenarios and the same reward serve both. The benchmark builds
distribution; the gym + hosted leaderboard accumulate the trajectory dataset.

## 6. Threat model and safety scope

- Attackers are **curated, well-known vulnerability classes**, used to harden
  defenses — not a pipeline for finding novel zero-days in live contracts.
- Adaptive/co-evolved attackers (future work) are confined to **simulation**.
- The deployed analog of a trained defense is a detector plus **bounded,
  reversible** actions (pause, rate-limit). Irreversible actions (moving user
  funds) stay human/governance-gated and are out of scope for autonomous control.
- No attribution, deanonymization, or offensive "hack-back." Out of scope by
  policy.

## 7. Roadmap

1. Scenario 02 — oracle/price manipulation (local mock AMM) is implemented; the
   forked-mainnet flash-loan variant is next.
2. Scenario 03 — oracle manipulation.
3. Scenario 04 — governance takeover.
   Co-evolution (attacker drain-rate vs defender window/cap) is implemented; see
   `aegis-gym/coevolve.py` and docs/PAPER.md. Per-address/behavioral defenses are
   the identified next escalation.
4. Scenario 05 — honeypot/canary tripwire (decoy target whose first touch trips
   the breaker before the real vault is reachable).
5. `aegis-gym` Python wrapper over the Foundry scorer (done; bandit reference
   agent). Next: continuous/multi-parameter defenses and a real policy-gradient
   agent.
6. Hosted leaderboard (Cloudflare Workers + D1) for submissions and trajectory
   capture.
