# Licensing & the open-core boundary

Aegis is **open-core**. The line between what is free and what is the company's
proprietary asset is drawn here, explicitly — so there is no ambiguity for users,
contributors, or investors.

## The open core — MIT (this repository)

Free to read, fork, self-host, and integrate. This is the funnel: credibility,
adoption, and the reference implementation everyone can audit.

- `src/` — the `IDefense` interface and the **reference** guards (rate-limit,
  per-address invariant, oracle/consensus/TWAP/price-impact, vault-share,
  pessimistic pricing).
- `test/` — the benchmark, fork tests, and the exploit replays.
- `aegis-gym/` — the benchmark harness and the **research** training ground
  (the pure-Python simulation used to prove mechanisms).
- `docs/`, `examples/` — methodology, the integration guide, the reference pool.

A competitor may take all of this. That is intended — it is marketing.

## The proprietary product — all rights reserved (NOT in this repository)

These are the company's IP. They are **not** MIT, **not** published here, and a
fork of the open core does not include them:

1. **Aegis Sentinel** — the operated, real-time monitoring service: the
   production keeper that watches live mainnet, the alerting/auto-pause
   orchestration, multi-tenant infrastructure, dashboards, and SLA.
2. **The data** — the cross-protocol price/telemetry and exploit corpus that
   *accumulates from operating Sentinel*. Every client's oracle stream compounds
   into a dataset no single defender — or fork — can reconstruct. This is the
   real moat.
3. **Production defense policies** — the trained, production-tuned model weights
   and thresholds (distinct from the open research sim's toy configs).
4. **The "Aegis Sentinel" name and brand.**

## Why an MIT core is still defensible (standard open-core)

The critique "MIT = anyone forks it = no moat" is correct *about the code* and
wrong *about the business*. The same is true of Sentry, GitLab, Grafana, and
CockroachDB: the code is open, the **operated service + the proprietary data +
the brand** are the company. A well-capitalized competitor can fork our guards,
but it cannot fork:

- the **running service** (infra, integrations, SLA, the trust of being the
  incumbent that already watches a protocol's oracle),
- the **compounding multi-protocol dataset** (it only exists by operating the
  service — a fork starts at zero),
- the **track record** ("Aegis caught attack X"),
- the **brand and relationships**.

If the moat ever needs to be hardened further, the operated engine can adopt a
source-available license (BSL 1.1) — but the data-and-service moat does not
depend on it.

## Using Aegis commercially

- **Self-hosting the open core:** free, forever, under MIT. Build your own
  monitoring on top — we want you to.
- **The hosted Aegis Sentinel service** (operated monitoring, alerting,
  auto-pause, the dataset): a commercial agreement. See `business/` materials or
  contact the maintainer.
