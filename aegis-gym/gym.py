"""Aegis gym — a thin RL environment over the Foundry scorer.

Each `step(cap_eth)` deploys a RateLimit defense with that cap, runs the
Scenario 01 exploit and the legitimate-traffic suite on-chain, and returns the
execution-derived reward. No human labels: the EVM is the verifier.
"""
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RUN_JSON = ROOT / "scoring" / "run.json"
_FOUNDRY_BIN = str(Path.home() / ".foundry" / "bin")


class AegisReentrancyEnv:
    """Discrete action space: the per-block outflow cap, in whole ether."""

    actions = list(range(0, 15))  # candidate caps: 0 .. 14 ether

    def __init__(self):
        env_path = os.environ.get("PATH", "")
        if _FOUNDRY_BIN not in env_path:
            env_path = f"{env_path}:{_FOUNDRY_BIN}"
        self._base_env = {**os.environ, "PATH": env_path}

    def step(self, cap_eth: int):
        env = {**self._base_env, "AEGIS_CAP": str(cap_eth)}
        subprocess.run(
            ["forge", "test", "--match-test", "test_scoreOne", "-q"],
            cwd=ROOT, env=env, check=True, capture_output=True,
        )
        info = json.loads(RUN_JSON.read_text())
        reward = info["reward_1e18"] / 1e18
        return reward, info
