# Contributing to Aegis

Aegis is a defensive research environment. Contributions are welcome under one
hard rule: **everything stays defensive** (see Scope below).

## Project shape

```
src/
  interfaces/IDefense.sol      # the single interface every defense implements
  lib/Reward.sol               # the verifiable reward function
  scenarios/<name>/            # Target + Attack(s) + (ctx convention)
  defenses/                    # submitted/reference defenses
test/
  base/<Scenario>Scenario.sol  # measurement core (attack + benign suites)
  <Scenario>.t.sol             # static scoreboard (asserts)
  Matchup.t.sol                # env-driven scorer the gym calls
aegis-gym/                     # Python: gym, single-agent, co-evolution, frontier
docs/                          # DESIGN, PAPER, SCENARIOS, ROADMAP
```

## Adding a defense

1. Copy `examples/TemplateDefense.sol` to `src/defenses/MyDefense.sol` and
   implement `IDefense.authorize(caller, selector, value, ctx)`.
2. It may be stateful or use transient storage; it must be honest about the
   scenario `ctx` it decodes.
3. Wire it into a scenario's `_buildDefense` helper and add a `DefenseConfig` in
   `aegis-gym/aegis/registry.py`, then score it on the EVM:
   ```bash
   cd aegis-gym
   python3 -m aegis score <scenario> <your-defense-substring> <attacker>
   python3 -m aegis leaderboard <scenario>
   ```
4. A good defense earns a positive reward by *precision*, not by blocking
   everything — the reward penalizes false positives 1:1. Full walkthrough:
   [examples/README.md](examples/README.md).

## Adding a scenario

See `docs/SCENARIOS.md`. In short: provide a `Target` with the one-line firewall
hook, at least one verified parameterized `Attack`, a `Benign` traffic suite,
document the `ctx` encoding, add an env-driven `MatchupNN.t.sol` scorer, and
register one `Scenario(...)` entry in `aegis-gym/aegis/registry.py` — which wires
it into the leaderboard, generalization study, and arms race automatically.

## Standards

- Solidity `^0.8.24`, `forge fmt`, EVM `cancun`.
- Every scenario must include a baseline test proving the undefended target is
  actually exploitable (so a passing defense is meaningful).
- Python: standard library only for the reference agents; keep them small.

## Scope (non-negotiable)

Aegis trains and measures **defenses**. Do not contribute tooling whose purpose
is to discover or launch attacks on live systems, to deanonymize or retaliate
against actors, or to give offensive uplift. Attacks here are curated, well-known
vulnerability classes used as training/evaluation fixtures, and adaptive
attackers are confined to simulation.
