# Aegis — common tasks
.PHONY: install build test fmt bench leaderboard verify trajectories rl-train learn coevolve frontier oracle generalize clean

install:
	forge install foundry-rs/forge-std --no-commit || true

build:
	forge build --sizes

test:
	forge test -vv

fmt:
	forge fmt

# unified benchmark across ALL registered scenarios: ranks every defense and
# runs the train/test generalization study, writing scoring/leaderboard.json
# and the published LEADERBOARD.md.
bench:
	cd aegis-gym && python3 -m aegis bench

# print the leaderboard for all scenarios (no file output)
leaderboard:
	cd aegis-gym && python3 -m aegis leaderboard

# assert the benchmark invariants on the EVM (structural tops every scenario and
# generalizes; threshold/rate defenses overfit) — the CI "living benchmark" gate
verify:
	cd aegis-gym && python3 -m aegis verify

# summarize the compounding trajectory ledger (every scored matchup is recorded)
trajectories:
	cd aegis-gym && python3 -m aegis trajectories

# continuous policy-gradient agent: learns a robust (window, cap) breaker from
# the verifiable worst-case reward (writes scoring/training.json)
rl-train:
	cd aegis-gym && python3 -m aegis train reentrancy

# single-agent learning demo (epsilon-greedy bandit discovers the optimal cap)
learn:
	cd aegis-gym && python3 train.py

# attacker/defender arms race (produces scoring/coevolution.json)
coevolve:
	cd aegis-gym && python3 coevolve.py

# rate-based vs behavioral defense comparison
frontier:
	cd aegis-gym && python3 frontier.py

# scenario 02 (oracle manipulation) frontier reproduction
oracle:
	cd aegis-gym && python3 oracle_frontier.py

# train/test generalization study (both scenarios)
generalize:
	cd aegis-gym && python3 generalize.py

clean:
	forge clean && rm -f scoring/run.json scoring/matchup.json scoring/matchup02.json scoring/matchup03.json scoring/matchup04.json scoring/results.json
