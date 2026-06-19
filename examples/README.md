# Examples — add and score a defense

This walkthrough takes you from zero to a scored defense in a few minutes.

## 1. Write a defense

Copy the template into the source tree:

```bash
cp examples/TemplateDefense.sol src/defenses/MyDefense.sol
```

Rename the contract to `MyDefense` and implement `authorize`. A defense returns
`true` to allow an action and `false` to block it. The reward penalizes false
positives 1:1, so you only score well by being **precise** — stop the exploit,
keep legitimate users alive.

The strongest defenses enforce an **invariant** (e.g. "you cannot withdraw more
than your recorded balance in one transaction", "only the admin may call this")
rather than fit a numeric threshold. Invariant-based defenses are the ones that
generalize to unseen attackers — see [LEADERBOARD.md](../LEADERBOARD.md).

## 2. Wire it into a scenario

Each scenario's env-driven scorer selects a defense family by an `AEGIS_DEF`
(or `AEGIS_GUARD`) string in its `_buildDefense` helper (e.g.
`test/base/ReentrancyScenario.sol`, `AccessScenario.sol`). Add a branch that
constructs `MyDefense`, then expose it as a `DefenseConfig` in
`aegis-gym/aegis/registry.py` so it appears on the leaderboard.

## 3. Score it on the EVM

```bash
cd aegis-gym

# one matchup (scenario, defense-label-substring, attacker strength)
python3 -m aegis score reentrancy mydefense 2

# worst-case ranking across the whole attacker grid
python3 -m aegis leaderboard reentrancy

# does it generalize to unseen attackers?
python3 -m aegis generalize reentrancy
```

## 4. Open a PR

Run `forge test` (green) and the Python unit tests, then open a PR using the
template. Include your `aegis score` / `aegis leaderboard` output.

> Reminder: Aegis is strictly defensive. Contribute defenses and scenarios, not
> tooling to attack live systems. See [../CONTRIBUTING.md](../CONTRIBUTING.md).
