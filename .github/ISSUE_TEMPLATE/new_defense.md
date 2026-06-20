---
name: New defense submission
about: Propose a defense to be scored on the Aegis leaderboard
title: "[defense] <short name> for <scenario>"
labels: ["defense"]
---

## Defense

- **Scenario(s) it targets:** (reentrancy / oracle / access / …)
- **Family:** rate/threshold or structural/invariant
- **One-line idea:** what invariant or signal does `authorize` use?

## `ctx` it decodes

Which scenario context does it read, and how does it decide allow/block?

## Self-reported score

Paste the output of:

```bash
cd aegis-gym
python3 -m aegis score <scenario> <your-defense-substring> <attacker>
# and ideally the worst-case row from:
python3 -m aegis leaderboard <scenario>
```

## Checklist

- [ ] Implements `IDefense` (`src/defenses/…`).
- [ ] Earns a positive reward by **precision** (does not just block everything).
- [ ] Stays within the defensive scope (see CONTRIBUTING.md).
