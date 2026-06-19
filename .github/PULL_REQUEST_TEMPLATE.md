<!-- Thanks for contributing to Aegis. Keep everything defensive (see CONTRIBUTING.md). -->

## What this changes

-

## Type

- [ ] New defense
- [ ] New scenario (vulnerability class)
- [ ] Environment / gym / scorer
- [ ] Docs
- [ ] Fix

## Verification

```bash
forge test                              # all suites green
cd aegis-gym && python3 -m unittest discover -s tests   # python logic tests
# for a new defense/scenario, paste the relevant `aegis score` / `aegis leaderboard` output:
```

## Checklist

- [ ] `forge test` is green.
- [ ] `forge fmt` applied (Solidity).
- [ ] New scenarios add a baseline test proving the undefended target is exploitable.
- [ ] New scenarios are registered in `aegis-gym/aegis/registry.py`.
- [ ] Stays within the defensive scope.
