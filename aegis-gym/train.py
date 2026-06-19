"""A minimal RL agent that LEARNS the optimal defense from verifiable reward.

This is an epsilon-greedy bandit over the cap action space. It is told nothing
about reentrancy, whales, or the right answer. It only proposes a cap, observes
the on-chain reward, and updates. Over a handful of episodes it concentrates on
the cap that stops the drain without harming legitimate users.

The point is not the algorithm (a bandit is deliberately simple); it is that the
reward signal is real, execution-grounded, and label-free — so the same loop
scales to richer defense parameterizations and learned classifiers.
"""
import random
from gym import AegisReentrancyEnv

EPISODES = 18
SEED = 7


def main():
    random.seed(SEED)
    env = AegisReentrancyEnv()
    actions = env.actions

    Q = {a: 0.0 for a in actions}   # value estimate per cap
    N = {a: 0 for a in actions}     # times each cap was tried

    print(f"{'ep':>3}  {'mode':<8}{'cap':>4}{'reward':>8}   best so far")
    print("-" * 44)

    best_a, best_r = None, -1.0
    for ep in range(1, EPISODES + 1):
        eps = max(0.1, 1.0 - ep / EPISODES)  # explore early, exploit late
        if random.random() < eps:
            a, mode = random.choice(actions), "explore"
        else:
            a, mode = max(Q, key=Q.get), "exploit"

        r, info = env.step(a)
        N[a] += 1
        Q[a] += (r - Q[a]) / N[a]     # incremental sample-average update

        if r > best_r or (r == best_r and best_a is not None and a < best_a):
            best_a, best_r = a, r

        print(f"{ep:>3}  {mode:<8}{a:>4}{r:>8.2f}   cap={best_a} (r={best_r:.2f})")

    learned = max(Q, key=Q.get)
    print("-" * 44)
    print(f"learned policy: cap = {learned} eth  (Q={Q[learned]:.2f})")
    print("optimal plateau is cap in [5, 10]; reward 1.0 means the drain is")
    print("stopped AND every legitimate user — whale included — gets through.")


if __name__ == "__main__":
    main()
