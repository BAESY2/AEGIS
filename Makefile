# Aegis — common tasks
.PHONY: install build test fmt bench leaderboard learn coevolve frontier oracle generalize clean

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

# single-agent learning demo (discovers the optimal rate cap)
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
	forge clean && rm -f scoring/run.json scoring/matchup.json scoring/matchup02.json scoring/matchup03.json scoring/results.json
