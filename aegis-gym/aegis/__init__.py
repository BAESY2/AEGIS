"""Aegis — a verifiable RL environment & benchmark for smart-contract defense.

Public surface:
    from aegis import registry, analysis, foundry
    from aegis.env import AegisEnv

Every score in this package is decided by contract execution on a forked EVM
via Foundry; Python only orchestrates and reports.
"""
from . import analysis, foundry, registry

__all__ = ["analysis", "foundry", "registry"]
__version__ = "0.2.0"
