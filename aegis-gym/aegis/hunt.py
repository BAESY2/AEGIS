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
