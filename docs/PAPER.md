# Co-evolving Attackers and Defenders over a Verifiable EVM Reward

*Preliminary report. Aegis project.*

## Abstract

Real-time on-chain defense has matured into commercial products, but the layer
beneath them — an open, reproducible environment in which a defense can be
*trained* and *objectively measured* — is missing. We present **Aegis**, a
benchmark and reinforcement-learning environment for smart-contract defense whose
reward is computed entirely from contract execution on a forked EVM, requiring no
human labels. Using a reentrancy scenario, we show two things. First, a defense
optimized against the obvious fast exploit overfits catastrophically: it scores
perfectly against that exploit yet saves **0%** of funds, in the worst case,
against a family of *patient* attackers that drain slowly to evade a per-block
rate limit. Second, co-evolving the attacker and defender over the verifiable
reward drives the defender from a per-block limiter to a windowed circuit breaker
and raises worst-case funds saved from **0.00 to 0.50**, while also exposing a
concrete frontier: rate-based defense alone cannot stop the most patient attacker
without harming legitimate "whale" users. We then cross that frontier with a
*behavioral* defense that enforces a per-address, per-transaction invariant; it
saves **100%** of funds across the entire attacker family with **zero** false
positives, dominating the best rate-based defender. The same pattern replicates in a second, structurally different scenario —
oracle/price manipulation. Most importantly, under a train/test split over the
attacker space, threshold/rate defenses **overfit** (perfect on seen attackers,
0% worst-case on held-out ones), while structural defenses **generalize** (equal
train and test performance) — in both scenarios. The environment, scorer, and
co-evolution loop are runnable end-to-end with `forge test` and a small Python
driver.

## 1. Introduction

Reinforcement learning with *verifiable rewards* (RLVR) — where an environment
mechanically checks an outcome rather than relying on human preference — has
become the most sought-after training signal in modern AI, with coding and
mathematics as the canonical domains. Smart-contract defense is natively
verifiable in the same sense: against a given exploit, a defended protocol either
retains its funds on a forked chain, or it does not.

Yet there is no open, shared environment that exploits this property for defense.
Monitoring vendors (Chainalysis Hexagate, Hypernative, SphereX) are closed SaaS;
academic efforts (EVMbench, SmartCoder-R1) are fragmented and lean offensive.
Aegis targets the missing piece: a public "firing range" where defenses are
trained and ranked by execution-grounded reward. This report focuses on one
question that range makes answerable — *does training a defense against a single
attack generalize, and does co-evolution help?*

## 2. Related work

- **RL environments / RLVR.** Verifiable-reward training is now a first-class
  budget line for frontier labs; coding and math seeded the field, and execution-
  based verification is the common thread. Aegis applies the same recipe to a new,
  natively verifiable domain.
- **On-chain defense.** Hexagate, Hypernative, and SphereX provide real-time
  detection and automated response (pause, revert, rate-limit). ERC-7265 codifies
  circuit breakers. These are the *deployed* analog of a trained Aegis defense;
  Aegis is the environment that would train and benchmark them.
- **Smart-contract security ML.** EVMbench measures agents' ability to find and
  exploit vulnerabilities; SmartCoder-R1 uses GRPO with compile/requirement/
  vulnerability checks to generate secure contracts. Both are largely generation-
  or offense-oriented; Aegis is defense- and environment-oriented.
- **Deception.** Canary tokens and honeypot contracts are established tripwires;
  a future Aegis scenario folds them in as early-warning triggers.

## 3. The Aegis environment

A **Scenario** is a vulnerable `Target`, a verified `Attack`, and a `Benign`
traffic suite. A **Defense** implements a single method,
`authorize(caller, selector, value, ctx) -> bool`, invoked by the target as a
one-line firewall hook at the top of each sensitive function; returning `false`
reverts the action. The **reward** is execution-derived:

```
reward = W_BLOCK . fundsSaved  -  W_FP . falsePositiveRate          (W_BLOCK = W_FP = 1)
```

The penalty term is essential: blocking everything earns the protection term but
pays the full false-positive penalty, netting zero — the same as no defense.
Positive reward requires *precision*, the real production constraint (a paused
protocol is itself an outage).

## 4. Co-evolutionary setup

**Scenario (01).** A reentrancy-drainable ETH vault (interaction-before-effects; the
balance update is `unchecked` to model the classic drainable bug). TVL = 10 ETH
of honest funds; the attacker seeds 1 ETH.

**Attacker strategy space.** A `PatientReentrancyAttacker` parameterized by
`takePerBlock`: each block it reenters to drain up to that amount, then stops.
Large `take` is a fast one-shot drain; small `take` is a slow, stealthy bleed
that stays under a per-block cap. Grid: `take ∈ {2,3,4,5,7,11}` ETH/block.
(`take = 1` is non-reentrant and cannot steal, so it is excluded.)

**Defender strategy space.** A `WindowedRateLimitDefense(window, cap)`: a
tumbling-window circuit breaker capping cumulative outflow over `window` blocks.
`window = 1` is a per-block limiter. Grid:
`(window,cap) ∈ {(1,5),(1,8),(4,5),(6,4),(8,3),(10,3)}`.

**Benign suite.** Three retail withdrawals (1 ETH) and one legitimate whale
(4 ETH), each spaced into its own window. A cap below 4 ETH false-positives the
whale.

**Horizon.** 12 blocks, modelling time-to-response; funds saved is measured at the
horizon (rate limiting bounds the bleed *rate*, not necessarily the total).

**Arms-race protocol.** Start the attacker population at the fast attacker. Each
round: (i) the defender best-responds, choosing the `(window,cap)` that maximizes
*worst-case* reward over the current attacker population; (ii) the attacker
best-responds, adding the `take` that most reduces that defender's funds saved.
Repeat until the attacker finds no new evasion.

## 5. Results

**Saved-fraction matrix** (horizon 12; rows = defender, columns = attacker
`take`; final column = false positives out of 4 legitimate actions):

| (window, cap) |  2   |  3   |  4   |  5   |  7   |  11  | FP |
|:-------------:|:----:|:----:|:----:|:----:|:----:|:----:|:--:|
| (1, 5)        | 0.00 | 0.00 | 0.00 | 0.00 | 1.00 | 1.00 | 0/4 |
| (1, 8)        | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 1.00 | 0/4 |
| (4, 5)        | 0.00 | 0.00 | 0.00 | 0.00 | 1.00 | 1.00 | 0/4 |
| (6, 4)        | 0.10 | 0.20 | 0.00 | 1.00 | 1.00 | 1.00 | 0/4 |
| (8, 3)        | 0.70 | 0.50 | 1.00 | 1.00 | 1.00 | 1.00 | 1/4 |
| (10, 3)       | 0.70 | 0.50 | 1.00 | 1.00 | 1.00 | 1.00 | 1/4 |

The per-block limiters `(1,5)` and `(1,8)` stop the fast attacker but collapse to
0.00 against patient attackers. The landscape is non-monotonic in `take` (e.g.
`(8,3)` saves more against `take=2` than `take=3`), an artifact of the discrete
window/horizon dynamics — and a reminder that hand-tuning is fragile.

**Arms race.**

| Round | Attacker population | Defender chosen | Worst-case reward | Attacker escalates to |
|:-----:|---------------------|:---------------:|:-----------------:|:---------------------:|
| 1 | {11}      | (1, 5) | +1.00 | take = 2 |
| 2 | {11, 2}   | (8, 3) | +0.45 | take = 3 |
| 3 | {11, 2, 3}| (8, 3) | +0.25 | take = 3 (no new evasion → equilibrium) |

The first patient escalation (`take=2`) forces the defender off the per-block
limiter onto a windowed breaker; the population then reaches an equilibrium the
attacker cannot improve on within the grid.

**Headline (worst-case funds saved over the full attacker grid).**

| Defender | Selection | Worst-case saved |
|----------|-----------|:----------------:|
| (1, 5)   | tuned on fast attacker only | **0.00** |
| (8, 3)   | co-evolved | **0.50** |

Co-evolution yields a **+0.50** absolute improvement in worst-case funds saved.

**Crossing the frontier with a behavioral defense.** The matrix above is bounded
by what outflow rate can express. We add `PerAddressInvariantDefense`, which
ignores rate entirely and instead enforces the invariant the buggy vault forgets:
within one transaction, an address cannot withdraw more than its recorded
balance. The per-caller cumulative is tracked in transient storage (EIP-1153), so
it accumulates across reentrant calls in a transaction and resets between
transactions. Scored over the same grid:

| Defense | 2 | 3 | 4 | 5 | 7 | 11 | worst-case | FP |
|---------|:-:|:-:|:-:|:-:|:-:|:--:|:----------:|:--:|
| rate-based (8,3), co-evolved   | 0.70 | 0.50 | 1.00 | 1.00 | 1.00 | 1.00 | 0.50 | 1/4 |
| behavioral (per-addr invariant)| 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | **1.00** | **0/4** |

The behavioral defense stops fast and patient reentrancy at every drain rate and
never blocks a legitimate user, including the whale — a strict dominance that the
rate-based family provably cannot reach, because a maximally patient drain is
indistinguishable from legitimate activity by outflow alone.

### Generalization to a second vulnerability class

To check that the findings are not reentrancy-specific, we add **Scenario 02**:
oracle/price manipulation. A lending pool values collateral at an AMM *spot*
price; the attacker pumps that price within one transaction (knob: pump size) and
borrows against the inflated collateral. A `PriceDeviationGuard` blocks borrows
whose price deviates from a fixed reference beyond a threshold; a
`LaggedOracleGuard` instead compares spot to a one-block-lagged price.

Saved fraction (1 = exploit fully prevented) over pump sizes, with legitimate
false positives out of two honest borrows (one fair, one after genuine drift):

| Defense | pump 3 | 5 | 10 | 100 | FP |
|---------|:------:|:-:|:--:|:---:|:--:|
| fixed-anchor (≤609 bps) | 0.00 | 1.00 | 1.00 | 1.00 | 0/2 |
| fixed-anchor (≤300 bps) | 1.00 | 1.00 | 1.00 | 1.00 | 1/2 |
| lagged-oracle (≤300 bps)| 1.00 | 1.00 | 1.00 | 1.00 | **0/2** |

The same structure reappears unprompted: the fixed-anchor guard cannot both pass
genuine drift and stop a small same-block pump of equal magnitude (a small pump
is indistinguishable from organic movement by a fixed reference). The lagged
oracle crosses that floor — a single-block manipulation cannot move the lagged
price — stopping every pump with zero false positives. That two unrelated
vulnerability classes produce the same overfitting-and-crossing pattern is
evidence the methodology, not a quirk of reentrancy, is what's being measured.

### Train/test generalization to unseen attackers

The sharpest test of a defense is not in-sample performance but generalization:
does a defense selected against *seen* attackers hold up against *unseen* ones? We
split each scenario's attacker grid into disjoint train and test sets, select each
defense family by best-response on train only, and evaluate the frozen choice on
test. Worst-case reward (saved minus false-positive penalty):

| Scenario | Family | Trained config | Train | Test | Gap |
|----------|--------|----------------|:-----:|:----:|:---:|
| 01 reentrancy | rate-based | window 6, cap 4 | 1.00 | 0.00 | **1.00** |
| 01 reentrancy | behavioral (per-addr) | — | 1.00 | 1.00 | **0.00** |
| 02 oracle | fixed-anchor | ≤609 bps | 1.00 | 0.00 | **1.00** |
| 02 oracle | lagged-oracle | ≤300 bps | 1.00 | 1.00 | **0.00** |

(Scenario 01: train takes {5,7,11}, test {2,3,4}. Scenario 02: train pumps
{8,20,100}, test {2,3,6}.)

The result is unambiguous and identical across both vulnerability classes: the
threshold/rate families score perfectly on the attackers they were selected
against and collapse to zero worst-case on held-out attackers (a generalization
gap of 1.00), whereas the structural defenses transfer perfectly (gap 0.00).
Structural defenses generalize because they enforce an invariant — you cannot
withdraw beyond your balance in a transaction; you cannot move a lagged price in
one block — that holds regardless of the attacker's specific parameters, rather
than fitting a boundary to the attacks that happened to be in the training set.
This is the central result: **the environment makes defense generalization
measurable, and it cleanly separates defenses that overfit from defenses that
hold.**

## 6. Discussion and limitations

- **Rate-based defense has a floor.** Even the co-evolved `(8,3)` saves only
  0.50–0.70 against the most patient attackers and pays a false-positive cost
  (the whale, FP = 1/4). A maximally patient attacker draining at legitimate
  rates is provably indistinguishable from a legitimate whale by outflow alone.
  We cross this floor in Section 5 with a per-address behavioral invariant; the
  general lesson is that the *signal*, not the rate threshold, is what matters.
- **Single scenario, small grids.** Results are for one reentrancy vault with
  discrete, low-dimensional strategy spaces and a fixed horizon. They demonstrate
  the *methodology* (verifiable reward, overfitting, co-evolution), not a general
  security guarantee.
- **Simple optimizers.** Best-response over a grid is the simplest possible
  learner; a continuous parameterization with policy-gradient is future work. The
  contribution is the environment and the verifiable signal, not the algorithm.

## 7. Ethics and defensive scope

Aegis is defensive. Targets and exploits are curated, well-known vulnerability
classes used to train and measure defenses; the environment is not a tool for
discovering or launching attacks on live systems, performs no attribution or
"hack-back," and confines any adaptive attacker to simulation. The deployed
analog of a trained defense is a detector plus bounded, reversible actions
(pause, rate-limit); irreversible actions over user funds remain
human/governance-gated and out of scope for autonomous control.

## 8. Future work

1. Forked-mainnet scenarios: flash-loan price manipulation, oracle manipulation,
   governance takeover.
2. A honeypot/canary tripwire scenario (a decoy whose first touch trips the
   breaker before the real vault is reachable).
3. Behavioral defense families beyond the single-invariant case (cross-tx
   address reputation, graph features) and adversarial co-evolution against them.
4. Continuous defense parameterizations with a policy-gradient agent.
5. A hosted leaderboard that accumulates submitted attack/defense trajectories —
   the compounding dataset asset.

## Reproducibility

```bash
curl -L https://foundry.paradigm.xyz | bash && foundryup
forge install foundry-rs/forge-std
forge test                          # scenario + static scoreboard
cd aegis-gym && python3 train.py    # single-agent learning demo
cd aegis-gym && python3 coevolve.py # the arms race in this report
```

All numbers above are emitted by `coevolve.py` to `scoring/coevolution.json`.
