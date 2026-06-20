# Aegis backend — hosted-leaderboard scaffold

A dependency-free (standard-library) HTTP service that exposes the `aegis submit`
flow so submissions accumulate in one place — the mechanism behind the
multi-party dataset moat. This is a **scaffold**: the API and accumulation are
real and runnable; the production-hardening (sandboxed execution, auth, storage)
is the remaining work.

## Run

```bash
cd aegis-gym && python3 -m aegis bench   # generate scoring/leaderboard.json
python3 server/app.py                    # serves on :8000 (PORT to override)
```

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | liveness |
| GET | `/leaderboard` | the published leaderboard (`scoring/leaderboard.json`) |
| GET | `/submissions` | the accumulated submission ledger |
| POST | `/score` | body = Solidity source of `contract Submission is IDefense`; scores it on the reentrancy scenario and appends the result |

```bash
curl localhost:8000/health
curl localhost:8000/leaderboard
# scoring a submission requires execution to be explicitly enabled (see below):
AEGIS_ALLOW_EXECUTION=1 python3 server/app.py
curl -X POST --data-binary @submissions/Submission.sol localhost:8000/score
```

## Security — read before deploying

`POST /score` compiles and runs **submitted Solidity** via Foundry. Executing
untrusted code MUST be sandboxed: a disposable container with **no network**, and
hard CPU/memory/wall-clock limits. The scaffold therefore **disables execution by
default**; set `AEGIS_ALLOW_EXECUTION=1` only inside such a sandbox. The hosted
service is the one place that sees every vendor's submission — its value, and its
responsibility, is that aggregation.

## Why this exists

GitHub-native submission already works (`.github/workflows/submission.yml` scores
a `submissions/` PR and comments the rank). This service is the always-on form:
submit over HTTP, get scored, and every submission's trajectory accumulates as
the dataset asset no single defender can replicate.
