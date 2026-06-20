---
name: New scenario proposal
about: Propose a new vulnerability class for the benchmark
title: "[scenario] <vulnerability class>"
labels: ["scenario"]
---

## Vulnerability class

What real, well-known bug class does this model? (link a famous incident if any)

## The frontier it should expose

Aegis scenarios are most valuable when a **threshold/rate** defense *overfits*
(can be evaded by a subtle attacker and/or false-positives a legitimate hard
case) while a **structural/invariant** defense *generalizes*. Describe:

- **Attacker knob** (the strategy axis swept, e.g. drain rate, pump size): …
- **Threshold defense** (expected to overfit): …
- **Structural defense** (expected to generalize): …
- **Benign hard case** (the "whale" — legitimate but adversarial-looking): …

## Implementation notes

- Local or forked-mainnet? If forked, which protocol + pinned block?
- `ctx` encoding the target will pass to `authorize`: …

See [docs/SCENARIOS.md](../../docs/SCENARIOS.md) for the authoring + registry steps.
