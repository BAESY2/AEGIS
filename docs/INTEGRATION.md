# Integrating Aegis into your protocol

Aegis is a single-line firewall hook plus a library of defenses you can test,
benchmark, and deploy. This guide is for protocol teams (DEXes, lending markets,
treasuries, governors) who want to adopt it.

## 1. The one line

At the top of any sensitive function, ask a defense whether to allow the action:

```solidity
import {IDefense} from "aegis/interfaces/IDefense.sol";

contract YourProtocol {
    IDefense public immutable defense;

    function withdraw(uint256 amount) external {
        // ---- Aegis firewall hook ----
        if (address(defense) != address(0)) {
            bool allow = defense.authorize(msg.sender, msg.sig, amount, _ctx());
            require(allow, "AEGIS_BLOCKED");
        }
        // ------------------------------
        // ... your logic ...
    }
}
```

`authorize(caller, selector, value, ctx)` returns `true` to allow or `false` to
block (you revert). `ctx` is an ABI-encoded snapshot **you** define — the
contract between your function and any defense.

For a complete, runnable example of this exact diff wired into a swap path, see
[`examples/ProtectedSwapPool.sol`](../examples/ProtectedSwapPool.sol) and its
end-to-end test [`test/ProtectedPool.t.sol`](../test/ProtectedPool.t.sol): a
normal trade passes, a pool-draining trade reverts `AEGIS_BLOCKED` at the door,
and the same pool with no defense lets the drain through.

## 2. The `ctx` contract

Pass the defense exactly the signal it needs to make a precise decision. The
reference scenarios show the pattern:

| Threat | What to put in `ctx` | Defense that holds |
|--------|----------------------|--------------------|
| Reentrancy / drain | `(recordedBalance, vaultBalance)` | per-address per-tx balance invariant |
| Oracle / price manipulation | `(spotPrice, laggedPrice)` | one-block-lagged oracle / independent reference |
| Single-venue price manipulation | `(priceA, priceB, priceC)` from independent venues | multi-source consensus (block when one venue is an outlier) |
| Flash / single-block price manipulation | none — guard reads the pair's accumulators on-chain | Uniswap V2 time-weighted average (block when spot diverges from the TWAP) |
| Flash drain / sandwich setup (excessive trade footprint) | `(reserveIn, reserveOut, amountIn)` | price-impact cap (block a single swap that moves the pool past a bps threshold) |
| MEV / sandwich on a swap | `(outputAtSpot, outputAtReference)` | block when realized output << an independent reference (same mechanism as oracle) |
| Broken access control | `(admin)` | caller-is-admin authorization invariant |
| Flash-loan governance | `(priorVotes, currentVotes)` | snapshot: votes backed by prior-block holdings |

> Note: precise, *structural* signals (an invariant the bug forgot) generalize to
> attackers you have not seen; numeric rate/threshold signals overfit. See the
> [generalization result](../README.md#tldr--the-result-that-matters).

## 3. Pick (or write, or train) a defense

- **Reuse** a reference defense from `src/defenses/` (rate limit, per-address
  invariant, reentrancy lock, lagged oracle, owner-only, snapshot, Chainlink
  reference, …).
- **Compose** several with `CompositeDefense` (defense-in-depth) — but note
  stacking can inherit a member's false positives (`aegis space`).
- **Write your own** and score it before you ship: drop it into
  `submissions/<scenario>/Submission.sol` and run `python3 -m aegis submit
  <scenario>` to get your worst-case reward and rank.
- **Ask for a recommendation**: `python3 -m aegis recommend <scenario>` returns
  the defense to deploy for that threat, with its worst-case saved, false
  positives, generalization verdict, and model confidence.

## 4. Deploy with bounded, reversible actions

Aegis is defensive and conservative by design. The deployed analog of a scored
defense is a detector plus **bounded, reversible** responses — revert/pause/
rate-limit. Irreversible actions over user funds stay human/governance-gated.

## 5. Validate on your real state

Defenses can be tested against **live mainnet state** on a fork (see
`test/Fork*.t.sol`): real Uniswap V2 reserves, a real executed swap, the live
Chainlink ETH/USD feed, a three-source consensus across Uniswap V2, Sushiswap,
and Chainlink (`test/ForkConsensus.t.sol` executes a real swap to crash one
venue and shows the guard blocks the manipulated outlier while a genuine
price — all venues agreeing — passes), and a time-weighted-average guard read
straight from the pair's on-chain accumulators (`test/ForkTwap.t.sol` builds a
real 30-minute TWAP, crashes spot within a block, and shows a flash
manipulation moves spot but not the TWAP). Point `MAINNET_RPC_URL` at an
archive/full node and run `make fork` to validate a guard against your actual
deployment's conditions.

## Questions a protocol usually asks

- *Does it add risk?* The hook only ever **blocks** an action; it cannot move
  funds or change your logic.
- *Gas?* One external call to a small contract; structural guards are O(1).
- *False positives?* That is exactly what the reward penalizes — every defense is
  ranked by precision (`funds saved − false-positive rate`), so a defense that
  blocks legitimate users scores poorly and won't top the board.
