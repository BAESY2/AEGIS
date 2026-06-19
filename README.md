# Aegis

**A training ground for swarms of self-evolving smart-contract defense agents.**

> A single giant shield — an "Iron Dome" for DeFi — is expensive, centralized, and
> already being built by well-funded teams (Chainalysis Hexagate, Hypernative,
> SphereX). Aegis takes the other path: instead of one costly shield, train many
> cheap defense agents — "drones" — that learn by fighting attackers in a
> verifiable simulation, and prove themselves before they ever fly over real funds.

## Vision

On-chain attacks unfold in seconds and drain millions. The industry's answer is a
big, expensive, real-time shield bolted onto each protocol. That shield is the
*gun*. Aegis builds the *firing range*: the open, verifiable environment where
defense agents are trained, made to fight evolving attackers, and ranked by an
outcome the EVM itself certifies — funds saved, with no human labels.

The bet: defense is a learning problem, learning needs an environment, and the
environment that everyone's defenses train against becomes the most valuable layer
in the stack — because every match played in it leaves behind attack/defense data
that compounds. Cheap, self-evolving, swarming defense — drones, not one Dome.

This is an early but working system. The sections below are honest about what is
proven today versus what is on the roadmap.

---

## Project status

Past proof-of-concept: a verifiable environment with **two vulnerability classes**
(reentrancy, oracle manipulation) and **reproducible results** — co-evolution
beats single-attacker training (worst-case funds saved 0.00 -> 0.50), in both
classes a stronger defense (behavioral invariant / lagged oracle) crosses the
floor that threshold-based defenses hit (1.00, zero false positives), and under a
train/test split those structural defenses **generalize to unseen attackers**
(gap 0.00) while threshold/rate defenses **overfit** (gap 1.00). Not yet a large-scale platform; see
[docs/ROADMAP.md](./docs/ROADMAP.md). Paper draft: [docs/PAPER.md](./docs/PAPER.md).
Contributing: [docs/SCENARIOS.md](./docs/SCENARIOS.md), [CONTRIBUTING.md](./CONTRIBUTING.md).

## Why this exists

1. **Defense is now a learning problem, and learning needs an environment.**
   Reinforcement learning with *verifiable rewards* (math, code) is the most
   sought-after training signal in AI today. Smart-contract defense is natively
   verifiable: an exploit either drains funds on a forked chain, or it does not.
   That binary, execution-grounded outcome is a clean reward.

2. **No open standard exists.** Monitoring vendors are closed SaaS. Academic
   work (EVMbench, SmartCoder-R1) is fragmented and offense-leaning. There is no
   shared, runnable, defense-oriented environment — the SWE-bench of on-chain
   security. Aegis aims to be it.

3. **The asset compounds.** Every defense submitted and every scenario added
   accumulates a corpus of attack/defense trajectories — the durable, hard-to-
   replicate moat, owned by the range rather than any single defender.

## The core abstraction

A **Scenario** = a vulnerable `Target`, a verified exploit `Attack`, and a
`Benign` traffic suite.

A **Defense** implements one method:

```solidity
interface IDefense {
    function authorize(address caller, bytes4 selector, uint256 value, bytes calldata ctx)
        external returns (bool allow);
}
```

A protocol integrates a defense with a single firewall-hook line at the top of a
sensitive function. The defense decides allow/block per call.

The **Reward** is execution-derived and deliberately not gameable:

```
reward = W_BLOCK . attackBlocked  -  W_FP . falsePositiveRate        (range: -1 ... +1)
```

Blocking everything earns the block reward but pays the full false-positive
penalty — netting zero, the same as doing nothing. Positive scores require
*precision*: stop the exploit while keeping legitimate users alive. That is the
real problem, made measurable.

## Quickstart

```bash
curl -L https://foundry.paradigm.xyz | bash && foundryup   # install Foundry
forge test -vv                                              # run the scorer
```

### Reference scoreboard — Scenario 01 (reentrancy)

Produced directly by `forge test` in this repo:

| Defense    | Attack blocked | False positives | Reward |
|------------|:--------------:|:---------------:|:------:|
| NoDefense  | no             | 0 / 3           | 0.0    |
| Paranoid   | yes            | 3 / 3           | 0.0    |
| RateLimit  | yes            | 0 / 3           | **1.0** |

The do-nothing baseline and the block-everything strawman both net zero; only a
precise circuit-breaker scores. A machine-readable leaderboard is written to
`scoring/results.json`.

### Learning demo — the defense tunes itself

The scoreboard above uses a hand-picked cap (2 ether) that scores only 0.75 — it
false-positives a legitimate whale. `aegis-gym/` removes the hand-tuning: an agent
is told nothing about reentrancy or the right answer, and only proposes a cap,
observes the on-chain reward, and updates.

```
forge test                      # sanity-check the scenario
cd aegis-gym && python3 train.py # watch the agent learn
```

```
 ep  mode     cap  reward
  1  explore    2    0.75
  2  explore    0    0.00
  3  explore    8    1.00   <- discovers the plateau
 ...
 18  exploit    8    1.00
learned policy: cap = 8 eth (Q=1.00)
```

It converges to a cap in the optimal [5, 10] band: the reentrancy drain is
stopped AND every legitimate user, whale included, gets through — discovered, not
configured. The bandit is deliberately trivial; what matters is that the reward
is real, execution-grounded, and label-free, so the same loop extends to richer
defense parameter spaces and learned classifiers.

## Layout

```
src/
  interfaces/IDefense.sol          # the one interface every defense implements
  lib/Reward.sol                   # the verifiable reward function
  scenarios/reentrancy/            # Scenario 01: target + canonical exploit
  defenses/                        # reference defenses (RateLimit, Paranoid)
test/Reentrancy.t.sol              # the scorer (runs attack + benign, emits reward)
scoring/                           # machine-readable leaderboard output
docs/DESIGN.md                     # architecture, reward design, threat model
```

## Roadmap

- **Scenarios:** `01 reentrancy` (done) -> `02 flash-loan price manipulation` ->
  `03 oracle manipulation` -> `04 governance takeover` -> `05 honeypot/canary
  tripwire` (decoy target that trips a circuit breaker before real funds move).
  Scenarios 02-04 run against forked mainnet state.
- **Gym wrapper (done):** `aegis-gym/` exposes a Python `step()` over the Foundry
  scorer; a minimal epsilon-greedy agent **learns the optimal defense cap from
  verifiable reward alone** (see below).
- **Co-evolution (done):** an adaptive attacker (drain rate) and defender (window,
  cap) escalate over the verifiable reward. A defense tuned only on the fast
  exploit saves **0%** worst-case against patient attackers; the co-evolved
  defense saves **50%** — see [docs/PAPER.md](./docs/PAPER.md). Run it with
  `cd aegis-gym && python3 coevolve.py`.
- **Hosted leaderboard:** submit a defense, get scored, climb the board — and the
  submitted trajectories accumulate as the dataset.

## Scope and safety

Aegis is **defensive**. Targets and exploits are curated, well-known vulnerability
classes used to *train and measure defenses*. It is not a tool for discovering or
launching attacks against live systems, and it does not perform attribution,
"hack-back," or any offensive action. Contributions must stay within that scope.

## License

MIT. See [LICENSE](./LICENSE).
