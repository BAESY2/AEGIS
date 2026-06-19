"""Thin, dependency-free wrapper around the Foundry (`forge`) scorer.

Every Aegis match is decided by contract execution on the EVM, not by a Python
heuristic: this module just sets the scenario's environment variables, invokes
the right `forge test`, and reads back the machine-readable JSON the test wrote
to ``scoring/``. The EVM is the verifier; Python only orchestrates.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path

# Repo root = two levels up from this file (aegis-gym/aegis/foundry.py).
ROOT = Path(__file__).resolve().parents[2]
SCORING = ROOT / "scoring"
_FOUNDRY_BIN = str(Path.home() / ".foundry" / "bin")


def _path_with_foundry() -> str:
    """Return a PATH that includes the Foundry bin dir, if it exists."""
    path = os.environ.get("PATH", "")
    if Path(_FOUNDRY_BIN).is_dir() and _FOUNDRY_BIN not in path.split(os.pathsep):
        path = f"{path}{os.pathsep}{_FOUNDRY_BIN}"
    return path


def ensure_forge() -> str:
    """Return the path to the `forge` binary or raise a helpful error."""
    env_path = _path_with_foundry()
    found = shutil.which("forge", path=env_path)
    if not found:
        raise RuntimeError(
            "`forge` not found. Install Foundry:\n"
            "  curl -L https://foundry.paradigm.xyz | bash && foundryup\n"
            "  forge install foundry-rs/forge-std"
        )
    return found


def run_test(match_test: str, json_file: str, env_overrides: dict | None = None) -> dict:
    """Run a single forge test by name and return the JSON it emitted.

    Parameters
    ----------
    match_test   : value passed to ``forge test --match-test``.
    json_file    : filename under ``scoring/`` the test writes its result to.
    env_overrides: scenario knobs exported as environment variables (values are
                   stringified); these are the AEGIS_* vars the tests read.
    """
    ensure_forge()
    env = {**os.environ, "PATH": _path_with_foundry()}
    for key, value in (env_overrides or {}).items():
        env[key] = str(value)

    proc = subprocess.run(
        ["forge", "test", "--match-test", match_test, "-q"],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"forge test --match-test {match_test} failed:\n{proc.stdout}\n{proc.stderr}"
        )

    out = SCORING / json_file
    if not out.exists():
        raise RuntimeError(f"expected scorer output {out} was not written")
    return json.loads(out.read_text())
