"""Self-evolving AMM defense: an attacker search *discovers* the split-trade
evasion of a per-trade impact cap, and a defender best-responds with the
windowed cumulative cap that holds.

The Solidity fork tests are the ground truth — `test/ForkImpact.t.sol`,
`test/SplitTradeEvasion.t.sol`, and the on-chain `PriceImpactGuard` /
`CumulativeImpactGuard`. This module is the *agent / search* layer over the same
constant-product mechanics (the role `env.py` plays for the rate-limit
scenario), kept stdlib-only so `python3` is the only requirement. It exists to
show the result is found by search, not hand-coded: nobody tells the attacker to
split — it learns that splitting maximizes drain under a per-trade cap, and the
defender learns the window cap that bounds it.
"""
from __future__ import annotations

from dataclasses import dataclass

FEE_NUM = 997
FEE_DEN = 1000


@dataclass
class Pool:
    """A textbook constant-product pool (x*y=k) with a 0.30% fee.

    `reserve_in` is the token the attacker sells (e.g. WETH); `reserve_out` is
    the token they drain (e.g. USDC). Mirrors the Solidity guards' math exactly.
    """

    reserve_in: float
    reserve_out: float

    def amount_out(self, amount_in: float) -> float:
        a = amount_in * FEE_NUM
        return (a * self.reserve_out) / (self.reserve_in * FEE_DEN + a)

    def impact_bps(self, amount_in: float) -> float:
        """Mid-price move (bps) a swap of `amount_in` would cause, on current reserves."""
        if amount_in <= 0 or self.reserve_in <= 0 or self.reserve_out <= 0:
            return 0.0
        out = self.amount_out(amount_in)
        new_in = self.reserve_in + amount_in
        new_out = self.reserve_out - out
        ratio = (new_out * self.reserve_in) / (self.reserve_out * new_in)
        return max(0.0, (1.0 - ratio) * 10000.0)

    def execute(self, amount_in: float) -> float:
        out = self.amount_out(amount_in)
        self.reserve_in += amount_in
        self.reserve_out -= out
        return out


class PerTradeCap:
    """Stateless per-trade impact cap — the guard the split attack defeats."""

    def __init__(self, max_bps: float):
        self.max_bps = max_bps

    def allows(self, pool: Pool, caller: str, amount_in: float) -> bool:
        return pool.impact_bps(amount_in) <= self.max_bps

    def open_window(self, caller: str, ref_reserve: float) -> None:
        pass

    label = "per-trade impact cap"


class WindowedCumulativeCap:
    """Stateful per-caller windowed cumulative-footprint cap — the fix.

    Tracks cumulative traded notional vs the liquidity at window open; blocks
    once it exceeds `max_window_bps`. One window per call to `coevolve`'s sim.
    """

    def __init__(self, max_window_bps: float):
        self.max_window_bps = max_window_bps
        self._cum: dict[str, float] = {}
        self._ref: dict[str, float] = {}

    def open_window(self, caller: str, ref_reserve: float) -> None:
        self._cum[caller] = 0.0
        self._ref[caller] = ref_reserve

    def allows(self, pool: Pool, caller: str, amount_in: float) -> bool:
        ref = self._ref.get(caller)
        if ref is None:
            self.open_window(caller, pool.reserve_in)
            ref = pool.reserve_in
        cum = self._cum.get(caller, 0.0) + amount_in
        self._cum[caller] = cum
        if ref <= 0:
            return True
        return (cum / ref) * 10000.0 <= self.max_window_bps

    @property
    def label(self) -> str:
        return f"windowed cumulative cap @ {self.max_window_bps:.0f} bps"


def attacker_best_response(
    make_pool, guard, chunk_grid=None, max_trades: int = 400
) -> dict:
    """Search the attacker's strategy space: a single chunk fraction of the
    reserve, repeated greedily for as long as the guard allows. Returns the
    fraction that drains the most, with that drain (as bps of `reserve_out`).

    The attacker is given no hint that splitting helps — it falls out of the
    search: under a per-trade cap, smaller chunks each clear the cap and the
    drain compounds; under a windowed cap, the cumulative limit caps total drain
    regardless of how the volume is sliced.
    """
    if chunk_grid is None:
        chunk_grid = [0.0025, 0.005, 0.01, 0.02, 0.05, 0.1, 0.25, 0.5]
    best = {"chunk_frac": 0.0, "drain_bps": 0.0, "trades": 0}
    for f in chunk_grid:
        pool = make_pool()
        guard.open_window("attacker", pool.reserve_in)
        start_out = pool.reserve_out
        trades = 0
        for _ in range(max_trades):
            amount_in = f * pool.reserve_in
            if amount_in <= 0 or not guard.allows(pool, "attacker", amount_in):
                break
            pool.execute(amount_in)
            trades += 1
        drain_bps = ((start_out - pool.reserve_out) / start_out) * 10000.0
        if drain_bps > best["drain_bps"]:
            best = {"chunk_frac": f, "drain_bps": drain_bps, "trades": trades}
    return best


def benign_passes(make_pool, guard, benign_bps: float, slices: int = 4) -> bool:
    """A legitimate trader doing `benign_bps` of volume in `slices` equal trades
    within one window must be allowed."""
    pool = make_pool()
    guard.open_window("benign", pool.reserve_in)
    per = (benign_bps / 10000.0) / slices * pool.reserve_in
    for _ in range(slices):
        if not guard.allows(pool, "benign", per):
            return False
        pool.execute(per)
    return True


def defender_best_response(make_pool, benign_bps: float, cap_grid=None) -> WindowedCumulativeCap:
    """Pick the tightest windowed cap that still admits `benign_bps` of honest
    volume per window — minimizing the attacker's per-window drain."""
    if cap_grid is None:
        cap_grid = [200, 300, 500, 750, 1000, 1500, 2000]
    chosen = None
    for c in sorted(cap_grid):
        guard = WindowedCumulativeCap(c)
        if benign_passes(make_pool, guard, benign_bps):
            chosen = WindowedCumulativeCap(c)
            break
    return chosen or WindowedCumulativeCap(max(cap_grid))


def coevolve(reserve_in: float = 1_000_000.0, reserve_out: float = 2_000_000_000.0,
             per_trade_bps: float = 200.0, benign_bps: float = 500.0) -> dict:
    """One round of the arms race. Returns a structured result for reporting/tests."""
    def make_pool():
        return Pool(reserve_in, reserve_out)

    # Round 0: defender deploys the per-trade cap; attacker best-responds.
    per_trade = PerTradeCap(per_trade_bps)
    atk0 = attacker_best_response(make_pool, per_trade)

    # Round 1: defender best-responds with the windowed cumulative cap.
    windowed = defender_best_response(make_pool, benign_bps)
    atk1 = attacker_best_response(make_pool, windowed)

    return {
        "per_trade_bps": per_trade_bps,
        "benign_bps": benign_bps,
        "round0": {"defense": per_trade.label, **atk0},
        "round1": {
            "defense": windowed.label,
            "window_cap_bps": windowed.max_window_bps,
            "benign_admitted": benign_passes(make_pool, windowed, benign_bps),
            **atk1,
        },
    }


def format_report(r: dict) -> str:
    lines = []
    lines.append("DEX defense co-evolution — attacker search vs defender best-response")
    lines.append("=" * 68)
    r0 = r["round0"]
    lines.append(f"\nRound 0  defense: {r0['defense']} @ {r['per_trade_bps']:.0f} bps")
    lines.append(
        f"  attacker discovered: chunks of {r0['chunk_frac']*100:.2f}% of the pool, "
        f"{r0['trades']} trades"
    )
    lines.append(f"  -> drained {r0['drain_bps']/100:.1f}% of the pool (per-trade cap evaded)")
    r1 = r["round1"]
    lines.append(f"\nRound 1  defense: {r1['defense']}")
    lines.append(
        f"  attacker best response: chunks of {r1['chunk_frac']*100:.2f}%, {r1['trades']} trades"
    )
    lines.append(f"  -> drained {r1['drain_bps']/100:.1f}% of the pool")
    lines.append(f"  legitimate {r['benign_bps']/100:.1f}%/window trader admitted: {r1['benign_admitted']}")
    reduction = (1 - (r1["drain_bps"] / r0["drain_bps"])) * 100 if r0["drain_bps"] else 0.0
    lines.append(
        f"\nEquilibrium: the windowed cap bounds attacker drain to the honest-throughput"
    )
    lines.append(
        f"level, cutting worst-case drain {reduction:.0f}% "
        f"({r0['drain_bps']/100:.1f}% -> {r1['drain_bps']/100:.1f}%) while honest volume passes."
    )
    return "\n".join(lines)
