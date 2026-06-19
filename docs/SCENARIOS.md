# Authoring a Scenario

A scenario is the unit the whole environment is built from. It must be runnable,
self-verifying, and honest about what "attack succeeded" means.

## The three pieces

1. **Target** — a contract with a single integration point: the firewall hook
   ```solidity
   if (address(defense) != address(0)) {
       require(defense.authorize(msg.sender, msg.sig, value, ctx), "AEGIS_BLOCKED");
   }
   ```
   Everything else is left exploitable on purpose, so the *defense* is what gets
   scored. Document the `ctx` encoding precisely — it is the contract between the
   target and any defense.

2. **Attack(s)** — one or more verified exploit contracts. Where the attack has a
   strategic degree of freedom (drain rate, leverage, number of addresses),
   parameterize it: that knob becomes the attacker's action space for
   co-evolution.

3. **Benign suite** — legitimate interactions, ideally including an adversarial-
   looking-but-legitimate case (the "whale"), so a lazy defense pays a
   false-positive cost.

## Reward

Reuse `Reward.score(fundsSavedOrBlocked, fpCount, benignTotal)` so scores are
comparable across scenarios. Funds-saved should be measured at a fixed response
horizon when the attack is gradual.

## Wiring

- Put measurement in `test/base/<Name>Scenario.sol` (an abstract `is Test`).
- A static scoreboard `test/<Name>.t.sol` with asserts (must include a baseline
  proving the undefended target is exploitable).
- An env-driven entry in `Matchup.t.sol` (or a sibling) so `aegis-gym` can score
  arbitrary (defense, attacker) pairs.

## Checklist

- [ ] Undefended target is provably exploitable (baseline test).
- [ ] At least one parameterized attack.
- [ ] Benign suite with a legitimate hard case.
- [ ] `ctx` encoding documented.
- [ ] Deterministic; no external network unless it is a forked-mainnet scenario
      (then pin the block).
