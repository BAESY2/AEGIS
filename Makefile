# Aegis — common tasks
.PHONY: install build test fork exploit fmt bench leaderboard verify trajectories space dataset classify recommend submit serve rl-train learn coevolve dex-coevolve frontier oracle generalize clean

install:
	forge install foundry-rs/forge-std --no-commit || true

build:
	forge build --sizes

test:
	forge test -vv

# forked-mainnet integration: run the oracle guards against REAL Uniswap V2
# state (skips automatically without a fork endpoint)
fork:
	MAINNET_RPC_URL=$${MAINNET_RPC_URL:-https://ethereum-rpc.publicnode.com} \
		forge test --match-contract Fork -vv

# real historical exploit replay (needs an ARCHIVE node for 2022 state):
# the Inverse Finance oracle manipulation, with the guard's signal firing on it
exploit:
	ARCHIVE_RPC_URL=$${ARCHIVE_RPC_URL:-https://eth.drpc.org} \
		forge test --match-contract ForkExploitInverse -vv

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

# quantify the combinatorial size of the configuration space (~10^10 matchups)
space:
	cd aegis-gym && python3 -m aegis space

# generate/extend the EVM-verified trajectory dataset (data/trajectories.jsonl)
dataset:
	cd aegis-gym && python3 -m aegis dataset --budget 200

# train a defense-outcome classifier on the dataset (data -> model loop)
classify:
	cd aegis-gym && python3 -m aegis classify

# recommend the defense to deploy for a scenario (the advisory product surface)
recommend:
	cd aegis-gym && python3 -m aegis recommend reentrancy

# score YOUR defense (submissions/Submission.sol) and see your rank
submit:
	cd aegis-gym && python3 -m aegis submit reentrancy

# run the hosted-leaderboard backend scaffold (stdlib only)
serve:
	python3 server/app.py

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

# AMM arms race: attacker search discovers the split-trade evasion; defender
# best-responds with the windowed cumulative cap that bounds it
dex-coevolve:
	cd aegis-gym && python3 -m aegis dex-coevolve

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
