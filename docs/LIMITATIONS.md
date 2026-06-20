# Limitations & honest threat model

This project is deliberately candid about what it has *proven* versus what it
*demonstrates* or *aspires to*. A defense benchmark that oversells itself is
worse than useless. Read this before citing any result.

## What the headline result is — and is not

**The generalization result (structural defenses transfer, threshold defenses
overfit) is a constructed demonstration, not field evidence.** The reference
scenarios were designed so that a structural invariant *exists* that cleanly
separates attack from benign traffic, and the threshold/rate defenses are tuned
to overfit the training attacker. The exact `train 1.00 / test 0.00` vs
`1.00 / 1.00` split falls out of that design. It is an honest, reproducible
*illustration* of a real phenomenon (invariants generalize; fitted boundaries
do not) on clean models — **it is not evidence that any particular structural
defense generalizes on real, messy, in-the-wild contracts.** Treat it as a
teaching benchmark and a methodology, not a measurement of the real world.

## Historical exploit replay — done for one real hack, with caveats

Most `test/Fork*.t.sol` tests run against **real mainnet state** but execute a
manipulating swap *we* construct. One test goes further:
`test/ForkExploitInverse.t.sol` replays the **Inverse Finance oracle
manipulation of 2 April 2022** on real archive state. It forks the SushiSwap
INV/WETH pool at two real blocks (before, and at the manipulation), reconstructs
the genuine time-weighted price from the pool's own on-chain accumulators over
that real window (~0.107 WETH/INV), and shows the manipulated spot at the
exploit block (~6.0 WETH/INV, a **56x** pump) diverges so far that a
consensus/deviation guard fed `(spot, TWAP)` returns `false`. A second,
independent signal fires on the same real hack: the attacker's manipulating swap
(300 WETH into a 46-WETH pool, inferred from the real reserve delta) is a 9823 bps
price impact, so `PriceImpactGuard` blocks it too. Both Aegis signals fire on the
**actual exploited state**.

Caveats, stated plainly: (1) it demonstrates the guard's *signal* fires on the
real manipulated price — it does **not** replay the attacker's full calldata
against the victim's own contracts; (2) it requires an **archive** node
(historical state at 2022 blocks), so it is gated on `ARCHIVE_RPC_URL` and skips
in normal CI; (3) it is **one** exploit. The method, the replayability boundary
(it captures persistent manipulations, not intra-tx flash ones), and the path to
a broader corpus are documented in [`docs/EXPLOITS.md`](./EXPLOITS.md). A broader
corpus remains the most valuable future work.

## The RL / "swarm" is low-dimensional today

The reinforcement-learning environment optimizes a *2-parameter* breaker
(window, cap) with REINFORCE, and `aegis dex-coevolve` runs an explicit
*search* (it is labelled as such). These honestly recover the right answers, but
they are closer to guided search over a small space than to a population of
learned, generalizing policies. The "swarm of self-evolving agents" is the
project's **direction**, not its current implementation. No multi-agent
population, learned attacker policy network, or emergent strategy exists yet.

## Gas: the stateful guards are not free

Measured per `authorize` call (`test/GasBench.t.sol`, includes call overhead):

| Guard | Path | Gas |
|-------|------|----:|
| `PriceImpactGuard` (stateless) | every call | ~3,700 |
| `MultiSourceConsensusGuard` (stateless) | every call | ~3,000 |
| `CumulativeImpactGuard` (stateful) | **cold** (first trade of a window per caller) | ~69,900 |
| `CumulativeImpactGuard` (stateful) | warm (window already open) | ~3,800 |

The stateful cumulative guard writes storage: the first trade of each window
pays ~3 cold `SSTORE`s (~70k gas), warm trades ~3.8k. A high-throughput DEX must
weigh that per-trade cost. The stateless guards are cheap; the `TwapGuard` adds
external `STATICCALL`s to the pair. **No guard here has been gas-golfed or
audited** — they are reference implementations, not production-optimized,
audited contracts.

## Precision on real markets, tested in the wild

The flip side of "does it block attacks?" is "does it block my real users?".
Two checks, both on real on-chain state:

- `test/ForkRealMarkets.t.sol` — a normal trade and an unmanipulated spot
  (== its own TWAP) pass on four diverse live pools.
- `aegis wild` (`aegis-gym/aegis/wild.py`) — replays **every real swap** from
  live Uniswap V2 pools over a real block range through the price-impact math and
  reports the actual false-positive rate. A run over ~30,000 recent blocks
  (~4 days) across USDC/WETH, DAI/WETH, WETH/USDT and WBTC/WETH scanned **6,847
  real swaps**. The impact distribution: **p50 = 0.2 bps, p99 = 23 bps,
  p99.9 = 44 bps, max = 274 bps (2.74%)**. A **2% impact cap would have blocked
  2 of 6,847 (0.03%)** genuine trades — and those two were genuinely large real
  trades just over the cap, which is exactly what a cap is meant to catch.
  Reproduce with `AEGIS_RPC_URL=<node> python3 -m aegis wild --blocks 30000`.

So on real data we now have **both** sides: a true positive (the guard blocks the
real Inverse Finance manipulation) and a 0.03% false-positive rate (2/6,847
genuine swaps, both real large trades). We report the honest 0.03%, not a
cherry-picked 0%. Caveats: the wild scan covers the pools and window sampled, not
all of DeFi; free public RPCs throttle large scans (the tool reports window
coverage and tolerates dropped windows — this run covered 56/64 windows).

### Not every guard is robust in the wild — and we say so

Wild-testing the **cross-venue consensus** guard (`aegis wild --consensus`,
Uniswap vs Sushiswap USDC/WETH) tells a less flattering but more useful story.
Over 2,500 real cross-venue samples the price deviation between the two honest
venues was **p50 = 9 bps but p99 = 246 bps, max = 352 bps (3.5%)** — Sushiswap's
shallower USDC/WETH pool genuinely drifts from Uniswap during normal trading. So
a naive **0.5% consensus threshold would false-positive on 14.4%** of real
samples; 1% → 5.3%; 2% → 1.8%. The consensus guard is **not** free in the wild:
it needs a threshold set above the real cross-venue spread (here ~2%+), and even
then it is far noisier than the price-impact guard's 0.03%.

This is exactly the point of testing in the wild rather than on constructed
scenarios: it shows *which* guard is safe at *which* threshold on real data. The
price-impact guard is robust; the cross-venue consensus guard requires care and
deeper-liquidity reference venues. We report this honestly rather than imply
every guard is clean.

**A refinement we tried and the data rejected.** A natural idea is to filter the
consensus false positives by requiring the deviation to *persist* across samples
(transient arbitrage gaps would be ignored). The wild data **refutes** it: the
instantaneous and persistent flag rates are nearly identical (e.g. 12.2% vs
11.8% at 0.5%). The cross-venue gap is **structural** — Sushiswap's shallow pool
drifts and *stays* drifted — not transient spikes, so temporal filtering does not
help. The honest fix is a deeper-liquidity reference (Uniswap V3 / Chainlink),
not a time filter on a shallow venue. We keep this negative result because it is
true and it points at the right fix.

**The fix, verified in the wild.** Re-running the consensus test with a **deep**
reference (`aegis wild --consensus --reference v3`, Uniswap V2 vs the Uniswap V3
USDC/WETH 0.05% pool) confirms it. Over **26,663** real samples the V2-vs-V3
deviation is **p50 = 14, p99 = 34, max = 252 bps**, and a 0.5% consensus
threshold flags just **0.31%** — versus **14.4%** against shallow Sushiswap. Same
guard, right reference: a ~46x drop in false positives. The wild lesson, closed
end to end: choose consensus venues by liquidity, not convenience.

## The dataset and classifier are in-distribution

The ~2,300-label corpus is generated by sweeping *our own* scenarios. A
classifier that predicts "will this defense hold?" is learning our synthetic
distribution; its accuracy is **not** evidence it predicts out-of-distribution
or real-world outcomes. The active-learning experiments report honest near-zero
gains on easy/large pools — we did not fabricate a win.

## The "moat" depends on adoption that does not yet exist

The compounding-dataset thesis (every submission accumulates a corpus no single
defender can replicate) is sound *if* multiple parties submit. Today there are
zero external submissions and the hosted scorer is a scaffold with execution
disabled by default. The moat is a plausible mechanism, not a realized asset.

## The combinatorial-space number is an upper bound

The ~10^10 figure counts parameter combinations × 2^N defense compositions. It
is arithmetic, not a claim that all of that space is meaningful — most
compositions are redundant or trivially dominated. It quantifies *scale*, not
*useful diversity*.

---

If you are evaluating Aegis: the **methodology** (verifiable EVM-scored rewards,
the generalization lens, the fork-validated guards, the search that rediscovers
the split-trade evasion) is the contribution. The specific numbers are honest
within their constructed settings. Anyone telling you a smart-contract defense
"generalizes" without a real-exploit corpus — including this repo — is showing
you a method, not a guarantee.
