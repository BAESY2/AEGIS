# Setup — spin it up and push

## 0. Prerequisites
- Foundry: `curl -L https://foundry.paradigm.xyz | bash && foundryup`
- Python 3.11+ (for the gym scripts)

## 1. Run it locally (verify it works before pushing)
```bash
forge install foundry-rs/forge-std   # one-time: pulls the test library
forge test                           # all suites should pass (green)
```
Optional — see the results from the paper reproduced live:
```bash
make learn        # single agent discovers the optimal rate cap
make coevolve     # attacker/defender arms race
make frontier     # rate-based vs behavioral defense
make oracle       # scenario 02 (oracle manipulation) frontier
make generalize   # train/test generalization (the headline)
```

## 2. Put it on GitHub
```bash
git init
git add .
git commit -m "Aegis: a training ground for self-evolving smart-contract defense agents"

# forge-std as a committed submodule (so others can clone and test):
forge install foundry-rs/forge-std
git add .gitmodules lib/forge-std
git commit -m "vendor forge-std"

# create an empty repo on github.com first (no README), then:
git remote add origin https://github.com/<you>/aegis.git
git branch -M main
git push -u origin main
```
CI (`.github/workflows/ci.yml`) runs `forge build` + `forge test` automatically on
push — a green check on the repo is your proof it works.

## 3. Cloners use it like this
```bash
git clone --recursive https://github.com/<you>/aegis.git
cd aegis && forge test
```
(If they forgot `--recursive`: `git submodule update --init`.)

## 4. The "done" bar for this milestone
- [ ] Repo public on GitHub with CI passing (green check).
- [ ] README renders with the vision + reproduced results tables.
- [ ] One other person runs `forge test` and confirms it's green.

That third box is the one that matters: shipping something a stranger can run.
