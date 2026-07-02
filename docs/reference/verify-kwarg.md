---
title: Verify Cache Seed
nav_order: 7
parent: Reference
---

# Verify Cache Seed (`verified:` kwarg)

`Transaction::Tx#verify` accepts an optional `verified:` keyword argument — a
`Set` of 32-byte binary wire-order wtxids that the caller asserts are already
verified. When a non-merkle-proven ancestor appears in this set, its subtree is
skipped; the caller warrants its script validity.

This is a **novel Ruby-side seam**. The TypeScript, Go, and Python reference SDKs
repeat the full walk on every `verify` call. This kwarg exists for wallet-side
persistent-cache short-circuit (see `bsv-wallet` HLR #516).

## What it is

A wallet that has already verified an ancestor transaction chain in a prior session
can pre-seed the in-call dedup set. The SDK skips enqueueing those ancestors'
subtrees, reducing redundant script executions to zero for the seeded portion of
the graph.

```ruby
# wallet has already verified source_tx in a prior session
cache = Set.new([source_tx.wtxid])
tx.verify(chain_tracker: tracker, verified: cache)
```

## Walk order {#walk-order}

The walk processes each queued transaction in this strict order:

| Step | Action | Bypassed by seed? |
|------|--------|-------------------|
| 1 | Skip if already `visited` (in-call dedup) | n/a |
| 2 | If `merkle_path` present → verify against chain tracker | **No** — defence-in-depth |
| 3 | If root transaction + `fee_model` given → validate fee | **No** — caller-passed policy |
| 4 | If wtxid is in seed → mark visited, skip subtree | Yes |
| 5 | Full input script verification (interpreter) | n/a |
| 6 | Output ≤ input satoshi check | n/a |
| 7 | Mark visited | n/a |

**Strict merkle ordering rationale:** a stale seed cannot mask a bad chain-anchor
claim. A transaction with a `merkle_path` always has its proof verified against the
chain tracker, regardless of whether its wtxid appears in the seed.

**Fee gate ordering rationale:** `fee_model` is a caller-passed policy, not a
cached claim about script validity. It runs before the seed short-circuit so a
wallet cannot accidentally disable fee validation by pre-seeding the subject
transaction's wtxid.

## Format contract {#format-contract}

- Elements must be **32-byte binary strings** (wire-order wtxid, `String#encoding`
  `ASCII-8BIT`), not hex strings.
- Use `BSV::Primitives::Hex.wtxid_from_hex(dtxid_hex)` to convert a display-order
  hex txid to a wire-order binary wtxid.
- The SDK validates the first element of a non-empty set at entry via
  `BSV::Primitives::Hex.validate_wtxid!` and raises `ArgumentError` with a
  `"looks like a hex txid — use wtxid_from_hex to convert"` hint if you pass a
  hex string by mistake.
- Passing a non-`Set` value (e.g. an `Array`) raises `ArgumentError`.

```ruby
# Wrong — hex string raises ArgumentError with a helpful hint
Set.new([source_tx.txid_hex])  # 64-char hex

# Correct — 32-byte binary wire-order wtxid
Set.new([source_tx.wtxid])
```

## Caller responsibilities {#caller-responsibilities}

- **Correctness.** The SDK cannot verify that a seeded wtxid actually passed
  script validation. If the cache is wrong, `verify` returns `true` for a subtree
  that has not actually been verified. The network is the backstop — ARC and miners
  will reject a broadcast whose inputs are invalid — but the wallet will have
  returned `true` in the interim.
- **Staleness invalidation.** If a transaction's script validity status changes
  (e.g. due to a chain reorganisation), remove its wtxid from the cache before
  calling `verify`.
- **Consensus-flag invalidation.** Cached wtxids are pinned to the consensus flags
  under which they were originally verified. Invalidate the cache when consensus
  flags change (rare on BSV mainnet, but worth noting).
- **Thread-safety.** Do not mutate the `Set` on another thread while `verify` is
  running. The SDK freezes the set on entry (idempotent — already-frozen sets are
  accepted) to catch accidental in-call mutation, but concurrent mutation from
  outside the call is not prevented.
- **No merkle bypass.** You cannot use the seed to bypass merkle-proof verification.
  If a transaction has a `merkle_path`, the proof is always verified.
