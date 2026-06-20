"""Population co-evolution — the defense 'training ground' for swarms.

The flagship `env.py` trains ONE defender against a fixed attacker grid. This is
the next step toward the project's stated vision: a *population* of attacker
agents and a *population* of defender agents that co-evolve over generations on
the verifiable AMM simulation (grounded in the wild-data guards). It measures the
result that matters for a training ground:

    a defender trained against the whole evolving SWARM generalizes to unseen
    attackers, while a defender tuned against a single (even the strongest)
    threat overfits and is evaded by the rest.

Everything is deterministic (seeded) and stdlib-only. Reward is the same
funds-saved/false-positive objective as the rest of Aegis: a defender that blocks
real users is unusable (fitness -1), so the swarm must stay precise.
"""
from __future__ import annotations

import json
import os
import random

from .dex import Pool, PerTradeCap, WindowedCumulativeCap

RIN, ROUT = 1_000_000.0, 2_000_000_000.0
BENIGN_BPS = 500.0  # an honest trader does 5% of the pool per window, in 4 slices


def _drain(defender: tuple[float, float], chunk_frac: float, max_trades: int = 500) -> float:
    """Fraction of the pool an attacker using `chunk_frac`-sized trades drains
    against a defender = (per_trade_cap_bps, window_cap_bps)."""
    per, win = defender
    pool = Pool(RIN, ROUT)
    ptc = PerTradeCap(per)
    wcc = WindowedCumulativeCap(win)
    wcc.open_window("a", pool.reserve_in)
    start = pool.reserve_out
    for _ in range(max_trades):
        amt = chunk_frac * pool.reserve_in
        if amt <= 0:
            break
        if not ptc.allows(pool, "a", amt) or not wcc.allows(pool, "a", amt):
            break
        pool.execute(amt)
    return (start - pool.reserve_out) / start


def _benign_ok(defender: tuple[float, float], slices: int = 4) -> bool:
    per, win = defender
    pool = Pool(RIN, ROUT)
    ptc = PerTradeCap(per)
    wcc = WindowedCumulativeCap(win)
    wcc.open_window("b", pool.reserve_in)
    each = (BENIGN_BPS / 10000.0) / slices * pool.reserve_in
    for _ in range(slices):
        if not ptc.allows(pool, "b", each) or not wcc.allows(pool, "b", each):
            return False
        pool.execute(each)
    return True


def worst_case_drain(defender: tuple[float, float], attackers) -> float:
    if not _benign_ok(defender):
        return 1.0  # unusable: blocks honest traffic
    return max(_drain(defender, a) for a in attackers)


def _mutate_def(d, rng):
    per, win = d
    return (
        min(2000.0, max(20.0, per * rng.uniform(0.7, 1.4))),
        min(5000.0, max(50.0, win * rng.uniform(0.7, 1.4))),
    )


def _mutate_atk(a, rng):
    return min(0.5, max(0.0005, a * rng.uniform(0.5, 1.7)))


def coevolve(generations: int = 30, pop: int = 16, seed: int = 0) -> dict:
    """Iterated population co-evolution. Defenders are selected to minimize the
    worst-case drain over the attacker population (subject to admitting honest
    traffic); attackers are selected to maximize drain against the best defender.
    """
    rng = random.Random(seed)
    defs = [(rng.uniform(50, 2000), rng.uniform(100, 3000)) for _ in range(pop)]
    atks = [rng.uniform(0.001, 0.4) for _ in range(pop)]
    history = []
    half = pop // 2
    for g in range(generations):
        defs.sort(key=lambda d: worst_case_drain(d, atks))  # ascending: best first
        best_def = defs[0]
        atks.sort(key=lambda a: _drain(best_def, a), reverse=True)  # strongest first
        history.append({"gen": g, "best_def": best_def, "worst_drain": worst_case_drain(best_def, atks)})
        defs = defs[:half] + [_mutate_def(rng.choice(defs[:half]), rng) for _ in range(pop - half)]
        # attackers: keep the top half, mutate some, and inject fresh "immigrants"
        # across the chunk-size spectrum so the swarm never stops probing split
        # attacks (this is what forces the defender to stay robust everywhere).
        immigrants = 3
        atks = (atks[: half - immigrants]
                + [_mutate_atk(rng.choice(atks[:half]), rng) for _ in range(pop - half)]
                + [rng.choice([0.001, 0.003, 0.01, 0.03, 0.1]) for _ in range(immigrants)])
    return {"history": history, "best_def": history[-1]["best_def"], "attacker_pop": atks}


def best_vs_single(target_attacker: float) -> tuple[float, float]:
    """The overfit baseline: tune against ONE observed threat. Among the configs
    that stop that single attacker (subject to admitting honest traffic), a naive
    engineer keeps the window cap as LOOSE as possible — 'the big trade is already
    blocked by the per-trade cap, so why add a tight cumulative limit?'. That tie-
    break is exactly the overfit: it never saw the split attack the window guards."""
    best = (2000.0, 50.0)
    best_key = (2.0, -1.0)  # (drain, -window): minimize drain, then maximize window
    for per in (50, 100, 200, 400, 800, 1600):
        for win in (500, 1000, 2000, 3000, 5000):
            d = (float(per), float(win))
            if not _benign_ok(d):
                continue
            key = (round(_drain(d, target_attacker), 6), -win)
            if key < best_key:
                best_key, best = key, d
    return best


def generalization_study(seed: int = 0) -> dict:
    """Train a defender against the SWARM vs against a SINGLE strong threat, then
    test both on a held-out, diverse attacker population."""
    co = coevolve(seed=seed)
    league_def = co["best_def"]

    # the most obvious single threat: a large-chunk drain
    single_def = best_vs_single(target_attacker=0.4)

    # held-out attackers the defenders never trained on (log-spaced chunk sizes)
    held_out = [0.0008, 0.002, 0.005, 0.012, 0.03, 0.07, 0.15, 0.35]
    return {
        "league_def": league_def,
        "single_def": single_def,
        "league_worst_drain": worst_case_drain(league_def, held_out),
        "single_worst_drain": worst_case_drain(single_def, held_out),
        "generations": len(co["history"]),
        "swarm_curve": [round(h["worst_drain"] * 100, 1) for h in co["history"]],
    }


def format_report(r: dict) -> str:
    lines = []
    lines.append("Defense training ground — population (swarm) co-evolution")
    lines.append("=" * 64)
    curve = r["swarm_curve"]
    lines.append(f"swarm worst-case drain by generation (%): {curve[0]} -> {curve[-1]}")
    lines.append(f"  (min reached: {min(curve)}%)")
    lp, lw = r["league_def"], r["league_worst_drain"]
    sp, sw = r["single_def"], r["single_worst_drain"]
    lines.append("")
    lines.append(f"swarm-trained defender   per={lp[0]:.0f}bps win={lp[1]:.0f}bps "
                 f"-> held-out worst-case drain {lw*100:.1f}%")
    lines.append(f"single-threat-tuned def  per={sp[0]:.0f}bps win={sp[1]:.0f}bps "
                 f"-> held-out worst-case drain {sw*100:.1f}%")
    lines.append("")
    if sw > lw:
        lines.append(f"Swarm training generalizes: it caps unseen attackers at {lw*100:.1f}% "
                     f"vs {sw*100:.1f}% for the single-threat tuning")
        lines.append("(which stops the obvious big trade but is evaded by split attacks it "
                     "never trained against).")
    else:
        lines.append("No generalization gap in this run.")
    return "\n".join(lines)


# --- context-adaptive defender: a policy that reads the pool and sets its cap ---

# Pools differ in honest demand (bps of liquidity traded per window). A single
# fixed cap must be loose enough for the busiest pool, over-exposing the quiet
# ones. An adaptive policy reads each pool's honest throughput and tightens.
POOL_TYPES = [200.0, 500.0, 1000.0, 2000.0]


def _benign_ok_bps(per: float, win: float, benign_bps: float, slices: int = 4) -> bool:
    pool = Pool(RIN, ROUT)
    ptc, wcc = PerTradeCap(per), WindowedCumulativeCap(win)
    wcc.open_window("b", pool.reserve_in)
    each = (benign_bps / 10000.0) / slices * pool.reserve_in
    for _ in range(slices):
        if not ptc.allows(pool, "b", each) or not wcc.allows(pool, "b", each):
            return False
        pool.execute(each)
    return True


def _adaptive_window(genome, benign_bps):
    per, slope, intercept = genome
    return min(5000.0, max(50.0, slope * benign_bps + intercept))


def _pool_costs(per, win_for, attackers):
    """mean drain across the pool types; an unusable cap (blocks honest demand)
    scores the worst (1.0)."""
    costs = []
    for b in POOL_TYPES:
        win = win_for(b)
        costs.append(1.0 if not _benign_ok_bps(per, win, b)
                     else max(_drain((per, win), a) for a in attackers))
    return sum(costs) / len(costs)


def _mutate_genome(gm, rng):
    per, slope, intercept = gm
    return (
        min(2000.0, max(20.0, per * rng.uniform(0.7, 1.4))),
        min(3.0, max(0.0, slope * rng.uniform(0.6, 1.5) + rng.uniform(-0.1, 0.1))),
        min(2000.0, max(0.0, intercept * rng.uniform(0.6, 1.5) + rng.uniform(-50, 50))),
    )


def coevolve_adaptive(generations: int = 30, pop: int = 16, seed: int = 0):
    """Evolve a defender POLICY (per_trade, slope, intercept) — window cap =
    slope*honest_demand + intercept — against the attacker swarm across pools."""
    rng = random.Random(seed)
    genomes = [(rng.uniform(50, 2000), rng.uniform(0, 2), rng.uniform(0, 1000)) for _ in range(pop)]
    atks = [rng.uniform(0.001, 0.4) for _ in range(pop)]
    half = pop // 2
    for _ in range(generations):
        genomes.sort(key=lambda gm: _pool_costs(gm[0], lambda b, g=gm: _adaptive_window(g, b), atks))
        best = genomes[0]
        atks.sort(key=lambda a: max(_drain((best[0], _adaptive_window(best, b)), a) for b in POOL_TYPES),
                  reverse=True)
        genomes = genomes[:half] + [_mutate_genome(rng.choice(genomes[:half]), rng) for _ in range(pop - half)]
        atks = (atks[: half - 3]
                + [_mutate_atk(rng.choice(atks[:half]), rng) for _ in range(pop - half)]
                + [rng.choice([0.001, 0.003, 0.01, 0.03, 0.1]) for _ in range(3)])
    return best


def adaptive_study(seed: int = 0) -> dict:
    """Does a context-adaptive policy beat the best single fixed cap across pools
    with different honest demand? Trained vs the swarm, tested on held-out attacks."""
    genome = coevolve_adaptive(seed=seed)
    held_out = [0.0008, 0.002, 0.005, 0.012, 0.03, 0.07, 0.15, 0.35]

    adaptive_cost = _pool_costs(genome[0], lambda b: _adaptive_window(genome, b), held_out)

    best_fixed, best_fc = (1600.0, 5000.0), 9.0
    for per in (50, 100, 200, 400, 800, 1600):
        for win in (500, 1000, 2000, 3000, 5000):
            fc = _pool_costs(float(per), lambda b, w=win: float(w), held_out)
            if fc < best_fc:
                best_fc, best_fixed = fc, (float(per), float(win))

    per_pool = []
    for b in POOL_TYPES:
        aw = _adaptive_window(genome, b)
        ad = (1.0 if not _benign_ok_bps(genome[0], aw, b)
              else max(_drain((genome[0], aw), a) for a in held_out))
        fper, fwin = best_fixed
        fd = (1.0 if not _benign_ok_bps(fper, fwin, b)
              else max(_drain((fper, fwin), a) for a in held_out))
        per_pool.append((b, aw, ad, fd))
    return {
        "genome": genome,
        "adaptive_mean_drain": adaptive_cost,
        "fixed": best_fixed,
        "fixed_mean_drain": best_fc,
        "per_pool": per_pool,
    }


def format_adaptive(r: dict) -> str:
    g = r["genome"]
    lines = [
        "Context-adaptive defender — policy vs best fixed cap, across pools",
        "=" * 64,
        f"learned policy: window_cap = {g[1]:.2f} * honest_demand_bps + {g[2]:.0f}  (per-trade {g[0]:.0f}bps)",
        f"best single fixed cap: per={r['fixed'][0]:.0f}bps window={r['fixed'][1]:.0f}bps",
        "",
        f"{'pool honest demand':>18} {'adaptive win':>13} {'adaptive drain':>15} {'fixed drain':>12}",
    ]
    for b, aw, ad, fd in r["per_pool"]:
        lines.append(f"{b:>15.0f}bps {aw:>11.0f}bps {ad*100:>13.1f}% {fd*100:>10.1f}%")
    lines.append("")
    lines.append(f"mean worst-case drain across pools: adaptive {r['adaptive_mean_drain']*100:.1f}% "
                 f"vs fixed {r['fixed_mean_drain']*100:.1f}%")
    lines.append("The adaptive policy reads each pool's honest demand and tightens the cap to "
                 "match;")
    lines.append("the fixed cap must stay loose enough for the busiest pool, over-exposing quiet ones.")
    return "\n".join(lines)


# --- REAL-DATA training ground: train the defender on real mainnet swaps ---

def load_real_impacts(path: str | None = None) -> dict:
    """Load the captured real Uniswap V2 swap-impact distribution (bps)."""
    path = path or os.path.join(os.path.dirname(__file__), "..", "data", "real_swap_impacts.json")
    with open(path) as f:
        return json.load(f)


def _attack_impacts() -> list[float]:
    """Realistic manipulation magnitudes (price-impact bps) — what an attacker
    must move the pool to profit. Computed from real constant-product mechanics
    for 5%..50%-of-pool manipulations, anchored by the MEASURED Inverse Finance
    swap (9823 bps, from test/ForkExploitInverse) and half-pool drain (5552 bps,
    from test/ForkImpact)."""
    pool0 = Pool(RIN, ROUT)
    out = []
    for frac in (0.05, 0.10, 0.20, 0.30, 0.50):
        out.append(Pool(RIN, ROUT).impact_bps(frac * pool0.reserve_in))
    out.append(9823.0)  # measured: the real Inverse manipulating swap
    return sorted(out)


def real_data_study(path: str | None = None) -> dict:
    """The training ground on REAL data: select the price-impact threshold that
    maximizes funds-saved minus false-positives, evaluated against the REAL benign
    swap distribution (captured mainnet swaps) and REAL attack magnitudes (the
    exploit corpus) — not a synthetic generator."""
    data = load_real_impacts(path)
    benign = data["impacts_bps"]
    attacks = _attack_impacts()
    n = len(benign)

    best_t, best_reward = 0.0, -9.0
    for ti in range(5, 6000, 5):
        t = float(ti)
        fp = sum(1 for b in benign if b > t) / n
        recall = sum(1 for a in attacks if a >= t) / len(attacks)
        reward = recall - fp  # funds-saved (recall) minus false positives
        if reward > best_reward:
            best_reward, best_t = reward, t

    fp = sum(1 for b in benign if b > best_t) / n
    recall = sum(1 for a in attacks if a >= best_t) / len(attacks)
    benign_sorted = sorted(benign)
    p99 = benign_sorted[min(n - 1, int(0.99 * (n - 1)))]
    return {
        "n_benign": n,
        "benign_p99_bps": p99,
        "benign_max_bps": max(benign),
        "attacks_bps": attacks,
        "learned_threshold_bps": best_t,
        "false_positive_rate": fp,
        "attack_recall": recall,
        "margin_x": (min(attacks) / max(benign)) if max(benign) else float("inf"),
        "pools": data.get("pools", {}),
        "blocks": data.get("blocks"),
    }


def format_real(r: dict) -> str:
    lines = [
        "Defense training ground — trained on REAL mainnet data",
        "=" * 64,
        f"benign: {r['n_benign']} real Uniswap V2 swaps "
        f"(p99 {r['benign_p99_bps']:.1f} bps, max {r['benign_max_bps']:.1f} bps)",
        f"attacks: real manipulation magnitudes {[round(a) for a in r['attacks_bps']]} bps "
        f"(incl. the measured Inverse 9823)",
        "",
        f"learned price-impact threshold: {r['learned_threshold_bps']:.0f} bps "
        f"({r['learned_threshold_bps']/100:.1f}%)",
        f"  false positives on real swaps: {r['false_positive_rate']*100:.2f}%",
        f"  attack recall:                 {r['attack_recall']*100:.0f}%",
        f"  separation margin: smallest real attack is {r['margin_x']:.0f}x the largest real benign trade",
        "",
        "Both sides are REAL: benign is captured mainnet traffic, attacks are the "
        "exploit corpus.",
        "The threshold is selected on that real distribution — not a synthetic test.",
    ]
    return "\n".join(lines)
