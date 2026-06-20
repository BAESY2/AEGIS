"""Tests for the dependency-free RL agents and environment spaces."""
import unittest

from aegis.agents import GaussianREINFORCE
from aegis.env import Box


class TestBox(unittest.TestCase):
    def test_clip_respects_bounds(self):
        b = Box(low=(1.0, 1.0), high=(12.0, 12.0))
        self.assertEqual(b.clip((0.0, 99.0)), (1.0, 12.0))
        self.assertEqual(b.clip((5.0, 6.0)), (5.0, 6.0))
        self.assertEqual(b.shape, (2,))


class TestGaussianREINFORCE(unittest.TestCase):
    def test_update_moves_mu_toward_rewarded_action(self):
        agent = GaussianREINFORCE(low=(0.0,), high=(10.0,), seed=0)
        agent.mu = [5.0]
        # a positive-advantage action above the mean should pull the mean up
        agent.update(action=(8.0,), reward=1.0, sigma=2.0)
        self.assertGreater(agent.mu[0], 5.0)

    def test_update_moves_mu_away_from_penalized_action(self):
        agent = GaussianREINFORCE(low=(0.0,), high=(10.0,), seed=0)
        agent.mu = [5.0]
        agent._baseline = 1.0  # so reward 0 is a negative advantage
        agent.update(action=(8.0,), reward=0.0, sigma=2.0)
        self.assertLess(agent.mu[0], 5.0)

    def test_mu_stays_within_bounds(self):
        agent = GaussianREINFORCE(low=(1.0,), high=(3.0,), seed=0)
        agent.mu = [2.0]
        for _ in range(50):
            agent.update(action=(3.0,), reward=10.0, sigma=1.0)
        self.assertLessEqual(agent.mu[0], 3.0)
        self.assertGreaterEqual(agent.mu[0], 1.0)

    def test_learns_a_concave_toy_objective(self):
        # reward(x) peaks at x=7; the agent's mean should drift toward it.
        class ToyEnv:
            def step(self, action):
                x = action[0]
                r = -((x - 7.0) ** 2) / 50.0
                return (0.0,), r, True, False, {"window": int(round(x)), "cap": 0}

        agent = GaussianREINFORCE(low=(0.0,), high=(12.0,), seed=3, sigma0=3.0)
        agent.mu = [1.0]
        agent.learn(ToyEnv(), episodes=80, verbose=False)
        self.assertGreater(agent.mu[0], 4.5, f"mu={agent.mu[0]} should move toward 7")


if __name__ == "__main__":
    unittest.main()
