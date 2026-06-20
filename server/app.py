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
import subprocess
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEADERBOARD = ROOT / "scoring" / "leaderboard.json"
LEDGER = ROOT / "server" / "submissions.jsonl"
SUBMISSION_SOL = ROOT / "submissions" / "Submission.sol"
GYM = ROOT / "aegis-gym"


def _score_submission(source: str) -> dict:
    """Write the submitted source and score it via `aegis submit` (sandbox me)."""
    if os.environ.get("AEGIS_ALLOW_EXECUTION") != "1":
        raise PermissionError(
            "execution disabled: set AEGIS_ALLOW_EXECUTION=1 only in a sandbox"
        )
    SUBMISSION_SOL.write_text(source)
    env = {**os.environ, "PATH": f"{os.environ.get('PATH','')}:{Path.home()}/.foundry/bin"}
    proc = subprocess.run(
        [sys.executable, "-m", "aegis", "submit", "reentrancy"],
        cwd=GYM, env=env, capture_output=True, text=True, timeout=300,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr or proc.stdout)
    result = json.loads((ROOT / "scoring" / "submission.json").read_text())
    record = {
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "scenario": "reentrancy",
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
        if self.path != "/score":
            return self._send(404, {"error": "not found"})
        length = int(self.headers.get("content-length", 0))
        source = self.rfile.read(length).decode()
        try:
            return self._send(200, _score_submission(source))
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
