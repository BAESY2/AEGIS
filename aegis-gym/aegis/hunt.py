"""Oracle risk scanner — quantify how cheap it is to manipulate a DEX pool that a
protocol might trust as a price oracle.

Defensive tool (an auditor's manipulation-cost calculator) that doubles as
responsible-disclosure bug-bounty recon: the Inverse Finance / NGP / many-others
pattern is a protocol reading a *spot* price off a *thin* DEX pool. If the
capital required to move that pool's price by the protocol's liquidation/borrow
threshold is small relative to the value the oracle secures, it is exploitable.

This module only READS public on-chain state and does arithmetic. It never sends
a transaction. Findings should go through a protocol's bug-bounty / responsible-
disclosure channel, never an exploit.
"""
from __future__ import annotations

import math

from . import wild  # reuse the stdlib JSON-RPC + getReserves helpers


def manipulation_cost_fraction(factor: float) -> float:
    """For a constant-product pool, the input (as a fraction of the moved-side
    reserve) needed to move the mid-price by `factor` (e.g. 2.0 = double).

        r' = sqrt(factor) * r  =>  amountIn ≈ r * (sqrt(factor) - 1)

    Fee is ignored (a small upward adjustment), so this is a lower bound."""
    if factor <= 1:
        return 0.0
    return math.sqrt(factor) - 1.0


def reserves_usd(url: str, pool: str, block: int | None = None,
                 token0_is_usd: bool = True) -> tuple[float, float]:
    """Return (reserve0_raw, reserve1_raw). Caller supplies decimals/pricing."""
    if block is None:
        block = wild._block_number(url)
    return wild._get_reserves(url, pool, block)


def onchain_cost(url: str, pool: str, factor: float, dec0: int = 18, dec1: int = 18,
                 block: int | None = None) -> dict:
    """Read a live pool and report the capital (in each token's human units) to
    move its mid-price by `factor`. No USD oracle needed — the caller judges the
    cost against the value the protocol's oracle secures. Read-only."""
    r0, r1 = reserves_usd(url, pool, block)
    frac = manipulation_cost_fraction(factor)
    # to move price0 (=r1/r0) up by `factor`, push token1 in: ~r1*(sqrt(f)-1)
    cost_token1 = (r1 * frac) / (10 ** dec1)
    # to move it down, push token0 in: ~r0*(sqrt(f)-1)
    cost_token0 = (r0 * frac) / (10 ** dec0)
    return {
        "pool": pool,
        "reserve0": r0 / (10 ** dec0),
        "reserve1": r1 / (10 ** dec1),
        "move_factor": factor,
        "cost_token0_to_move_down": cost_token0,
        "cost_token1_to_move_up": cost_token1,
    }


# --- source-level recon: fetch verified source and flag manipulable-oracle reads ---

# risky: a price read straight off live, flash-manipulable state
RISKY_PATTERNS = {
    "getReserves": "Uniswap-V2-style spot reserves read",
    "getAmountsOut": "router spot quote (manipulable in-block)",
    "getAmountOut": "AMM spot quote (manipulable in-block)",
    ".slot0": "Uniswap V3 instantaneous price (no TWAP)",
    "getPricePerFullShare": "vault share price (donation-inflatable)",
    "pricePerShare": "vault share price (donation-inflatable)",
    "balanceOf(address(this))": "balance-based pricing (flash-skewable)",
}
# mitigations: their presence lowers concern
MITIGATIONS = {
    "latestRoundData": "Chainlink feed",
    "price0CumulativeLast": "Uniswap V2 TWAP accumulator",
    "price1CumulativeLast": "Uniswap V2 TWAP accumulator",
    "observe(": "Uniswap V3 TWAP",
    "consult(": "TWAP consult",
}


def fetch_source(address: str, chain: int = 1) -> str:
    """Fetch verified contract source from Sourcify (free, no key). Returns the
    concatenated Solidity of all files, or '' if unverified/unavailable."""
    import json
    import urllib.request

    url = f"https://sourcify.dev/server/files/any/{chain}/{address}"
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (aegis-hunt)"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read())
    except Exception:
        return ""
    return "\n".join(f.get("content", "") for f in data.get("files", []) if f.get("name", "").endswith(".sol"))


def scan_source(source: str) -> dict:
    """Flag manipulable-oracle reads and note any mitigations present. A heuristic
    triage, not a proof — a hit means 'read this contract by hand'."""
    risky = {pat: source.count(pat) for pat in RISKY_PATTERNS if pat in source}
    mit = {pat: source.count(pat) for pat in MITIGATIONS if pat in source}
    suspicious = bool(risky) and not mit
    return {"risky": risky, "mitigations": mit, "suspicious": suspicious}


def format_scan(address: str, scan: dict) -> str:
    lines = [f"{address}:"]
    if not scan["risky"]:
        lines.append("  no obvious spot-price reads found")
        return "\n".join(lines)
    for pat, n in scan["risky"].items():
        lines.append(f"  [risky x{n}] {pat} — {RISKY_PATTERNS[pat]}")
    if scan["mitigations"]:
        for pat, n in scan["mitigations"].items():
            lines.append(f"  [mitigation x{n}] {pat} — {MITIGATIONS[pat]}")
    else:
        lines.append("  NO mitigation (Chainlink/TWAP) found near these reads — review by hand")
    return "\n".join(lines)


def assess(pool_liquidity_usd: float, secured_value_usd: float,
           move_factor: float) -> dict:
    """Given a pool's *moved-side* liquidity (USD), the value an oracle on it
    secures, and the price move an attack needs, return a risk verdict."""
    frac = manipulation_cost_fraction(move_factor)
    cost = pool_liquidity_usd * frac
    # profit proxy: an attacker who moves the price can extract up to ~the secured
    # value; net = secured - cost (very rough, but the right order-of-magnitude).
    profitable = cost < secured_value_usd
    return {
        "move_factor": move_factor,
        "manip_cost_usd": cost,
        "secured_value_usd": secured_value_usd,
        "cost_fraction_of_pool": frac,
        "profitable": profitable,
        "ratio_secured_to_cost": (secured_value_usd / cost) if cost else float("inf"),
    }


def format_assessment(name: str, a: dict) -> str:
    verdict = "EXPLOITABLE" if a["profitable"] else "likely safe"
    return (
        f"{name}: move x{a['move_factor']:.0f} costs ~${a['manip_cost_usd']:,.0f} "
        f"(={a['cost_fraction_of_pool']*100:.0f}% of the pool); secures "
        f"${a['secured_value_usd']:,.0f}  ->  {verdict} "
        f"(secured/cost = {a['ratio_secured_to_cost']:.1f}x)"
    )
