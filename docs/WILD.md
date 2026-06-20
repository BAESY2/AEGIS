# Wild evidence — the guards on real mainnet data

Constructed benchmarks show a guard blocks an attack you wrote. This page is the
opposite: every number below is measured on **real, live Ethereum mainnet state**
— real swaps, real reserves, a real historical exploit — not a model. It is the
evidence a protocol should actually weigh. Reproduce any line with the command
shown; nothing here is hand-set.

## The two questions, answered on real data

A defense is only useful if it **catches real attacks** *and* **doesn't block
real users**. We measure both, on-chain.

### 1. Does it catch a real attack? (recall)

The **Inverse Finance** oracle manipulation of 2 April 2022, replayed on archive
state (`make exploit`):

| Signal | On the real exploited state | Verdict |
|--------|------------------------------|---------|
| TWAP / consensus | manipulated spot 5.998 vs genuine TWAP 0.107 WETH/INV — a **56x** pump | blocked |
| price-impact | the attacker's 300-WETH swap into a 46-WETH pool = **9823 bps** impact | blocked |

Two structurally independent guards both fire on the actual hack.

### 2. Does it block real users? (precision)

Replaying genuine mainnet traffic through each guard (`aegis wild …`):

| Guard | Real sample | Distribution | False-positive rate |
|-------|-------------|--------------|---------------------|
| price-impact | 8,218 swaps, 7 pools (incl. SHIB/PEPE/LINK) | p99 = 23 bps | **0.02%** at a 2% cap |
| TWAP | 2,989 spot-vs-TWAP samples | p99 = 121 bps | **0.00%** at 2% (10.9% at 0.5%) |
| consensus (shallow ref) | 2,500 cross-venue samples | p99 = 246 bps | 14.4% at 0.5% — **too noisy** |
| consensus (deep V3 ref) | 26,663 cross-venue samples | p99 = 34 bps | **0.31%** at 0.5% |

## What real data taught us (that a constructed scenario could not)

0. **It holds on volatile assets, not just stablecoin pairs.** The price-impact
   evidence spans 7 real pools including the volatile SHIB/WETH, PEPE/WETH and
   LINK/WETH memecoin pairs — exactly where you'd expect violent moves. Even
   there, the largest genuine single-trade impact was 1.2%, and a 2% cap blocked
   0 of 1,371 memecoin swaps. The 2% threshold is robust across asset classes.

1. **The safe threshold is an empirical question.** Naive tight thresholds are
   noisy on *every* oracle guard, because ETH genuinely moves and shallow venues
   genuinely drift. A ~1–2% threshold is clean on real traffic — and a real
   manipulation (56x) is orders of magnitude above it. The gap between "normal
   volatility" and "attack" is wide, and real data measures exactly where to sit.

2. **The reference venue matters more than the guard.** The cross-venue consensus
   guard went from 14.4% to 0.31% false positives — a **~46x** improvement —
   purely by swapping a shallow Sushiswap reference for the deep Uniswap V3 pool.
   Same guard, right reference. You cannot learn this without real liquidity.

3. **A fix we tried and the data rejected.** Requiring the cross-venue deviation
   to *persist* did **not** reduce consensus false positives (12.2% → 11.8%): the
   gap is structural, not transient. We kept the negative result because it is
   true and it pointed at the real fix (the deep reference). See
   [`LIMITATIONS.md`](./LIMITATIONS.md).

## Reproduce

```bash
make exploit                                   # real Inverse Finance replay (needs ARCHIVE_RPC_URL)
AEGIS_RPC_URL=<node> python3 -m aegis wild                       # price-impact, 4 pools
AEGIS_RPC_URL=<node> python3 -m aegis wild --twap                # TWAP guard
AEGIS_RPC_URL=<node> python3 -m aegis wild --consensus           # consensus vs shallow Sushiswap
AEGIS_RPC_URL=<node> python3 -m aegis wild --consensus --reference v3   # vs deep Uniswap V3
```

Public RPCs throttle large scans; the tools report window coverage and tolerate
dropped windows. Block timestamps in the TWAP test are approximated from block
deltas. These are honest measurements within their stated scope — see
[`LIMITATIONS.md`](./LIMITATIONS.md) for the full threat model.
