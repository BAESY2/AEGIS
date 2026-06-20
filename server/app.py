#!/usr/bin/env python3
"""Aegis hosted-leaderboard backend — a dependency-free scaffold.

The local `aegis submit` flow, exposed over HTTP so submissions accumulate in one
place — the mechanism behind the multi-party dataset moat. Standard library only
(no Flask/FastAPI); run it with `python3 server/app.py`.

Endpoints
  GET  /health         -> {"ok": true}
  GET  /leaderboard    -> the published leaderboard (scoring/leaderboard.json)
  GET  /submissions    -> the accumulated submission ledger (server/submissions.jsonl)
  POST /score          -> body = Solidity source of `contract Submission is IDefense`;
                          scores it on the reentrancy scenario and appends the result.

SECURITY: POST /score compiles and runs SUBMITTED Solidity via Foundry. Executing
untrusted code MUST be sandboxed (containerized, no network, CPU/memory/time
limits) in production. This scaffold therefore DISABLES execution by default;
set AEGIS_ALLOW_EXECUTION=1 to enable it in a trusted/sandboxed environment.
"""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

ROOT = Path(__file__).resolve().parent.parent
LEADERBOARD = ROOT / "scoring" / "leaderboard.json"
LEDGER = ROOT / "server" / "submissions.jsonl"
GYM = ROOT / "aegis-gym"

# scenario -> submission slot path (reentrancy uses the top-level slot)
SLOTS = {
    "reentrancy": ROOT / "submissions" / "Submission.sol",
    "oracle": ROOT / "submissions" / "oracle" / "Submission.sol",
    "access": ROOT / "submissions" / "access" / "Submission.sol",
    "governance": ROOT / "submissions" / "governance" / "Submission.sol",
    "behavioral": ROOT / "submissions" / "behavioral" / "Submission.sol",
}


def _score_submission(source: str, scenario: str = "reentrancy") -> dict:
    """Write the submitted source and score it via `aegis submit` (sandbox me)."""
    if os.environ.get("AEGIS_ALLOW_EXECUTION") != "1":
        raise PermissionError(
            "execution disabled: set AEGIS_ALLOW_EXECUTION=1 only in a sandbox"
        )
    if scenario not in SLOTS:
        raise ValueError(f"unknown scenario '{scenario}'; options: {sorted(SLOTS)}")
    SLOTS[scenario].write_text(source)
    if str(GYM) not in sys.path:
        sys.path.insert(0, str(GYM))
    from aegis import submit as aegis_submit  # imported here so the server starts without forge

    result = aegis_submit.run(scenario)
    record = {
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "scenario": scenario,
        "result": result,
    }
    LEDGER.parent.mkdir(parents=True, exist_ok=True)
    with LEDGER.open("a") as fh:
        fh.write(json.dumps(record) + "\n")
    return record


class Handler(BaseHTTPRequestHandler):
    def _send(self, code: int, obj):
        body = json.dumps(obj, indent=2).encode()
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):  # quiet
        pass

    def do_GET(self):
        if self.path == "/health":
            return self._send(200, {"ok": True})
        if self.path == "/leaderboard":
            data = json.loads(LEADERBOARD.read_text()) if LEADERBOARD.exists() else {}
            return self._send(200, data)
        if self.path == "/submissions":
            rows = []
            if LEDGER.exists():
                rows = [json.loads(l) for l in LEDGER.read_text().splitlines() if l.strip()]
            return self._send(200, {"count": len(rows), "submissions": rows})
        return self._send(404, {"error": "not found"})

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path != "/score":
            return self._send(404, {"error": "not found"})
        scenario = parse_qs(parsed.query).get("scenario", ["reentrancy"])[0]
        length = int(self.headers.get("content-length", 0))
        source = self.rfile.read(length).decode()
        try:
            return self._send(200, _score_submission(source, scenario))
        except PermissionError as e:
            return self._send(403, {"error": str(e)})
        except Exception as e:  # noqa: BLE001
            return self._send(400, {"error": str(e)})


def main():
    port = int(os.environ.get("PORT", "8000"))
    srv = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"Aegis backend on :{port}  (execution "
          f"{'ENABLED' if os.environ.get('AEGIS_ALLOW_EXECUTION') == '1' else 'disabled'})")
    srv.serve_forever()


if __name__ == "__main__":
    main()
