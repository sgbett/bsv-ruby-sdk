---
title: Verify Cache Seed
nav_order: 7
parent: Reference
---

# Bidirectional Verify Cache (`verified:` kwarg)

`Transaction::Tx#verify` accepts an optional `verified:` keyword argument — a
`Hash` mapping 32-byte binary wire-order wtxids to `true`. It is a bidirectional
dedup surface: the caller can pre-seed it to short-circuit ancestor walks, and
the SDK writes into it as it walks so the caller can read the accumulated wtxid
set afterwards.

The `Hash` is mutated in place — the caller's object identity is preserved.
Passing `nil` (the default) tells the SDK to use an internal `Hash` the caller
cannot access.

This is a **novel Ruby-side seam**. The TypeScript, Go, and Python reference
SDKs repeat the full walk on every `verify` call. It exists for wallet-side
persistent-cache scenarios (see `bsv-wallet` HLR #516).

## Three usage patterns

### 1. Pre-seed (short-circuit)

Skip already-verified ancestors:

```ruby
# Wallet has already verified source_tx in a prior session.
cache = { source_tx.wtxid => true }
tx.verify(chain_tracker: tracker, verified: cache)
```

### 2. Post-read (accumulate)

Read the walked wtxids into a wallet-side persistent verification cache:

```ruby
walked = {}
tx.verify(chain_tracker: tracker, verified: walked)
walked.keys # => [subject_wtxid, ancestor1_wtxid, ...]
persistent_cache.store(walked.keys)
```

### 3. Bidirectional round-trip

Load a persistent cache, use it to short-circuit, and store the updated cache
back:

```ruby
cache = load_persistent_verified_cache
tx.verify(chain_tracker: tracker, verified: cache)
save_persistent_verified_cache(cache) # includes newly-walked wtxids
```

## Walk order {#walk-order}

The walk processes each queued transaction in this order:

| Step | Action | Bypassed by seed? |
|------|--------|-------------------|
| 0 | (before the loop) If `fee_model` given → validate root fee | **No** — fee is a caller-passed policy, not a cached script-validity claim |
| 1 | Skip if `verified[wtxid]` is truthy (top-of-loop dedup) | Yes — seeded and walked entries both hit here |
| 2 | If `merkle_path` present → verify against chain tracker | Yes — seeded wtxid short-circuits at step 1 before this runs |
| 3 | Verify each input script through the interpreter | Yes — seeded wtxid short-circuits at step 1 before this runs |
| 4 | Output ≤ input satoshi check | Yes — seeded wtxid short-circuits at step 1 before this runs |
| 5 | Mark `verified[wtxid] = true` | Reached only when step 1 didn't hit (walked live) |

**Trust contract.** A seeded wtxid short-circuits everything after step 0 —
including the merkle proof. The caller warrants full trust: script validity
AND chain-anchor claim. This is the intentional consequence of the single-Hash
presence-only design (see [Format contract](#format-contract)).

**Fee gate ordering rationale.** Fee validation is a caller-passed policy — it
lives outside the "already verified" claim the seed makes. If you pass a
`fee_model`, it runs once at the start of the call, regardless of what's in the
Hash. A wallet cannot accidentally disable fee validation by pre-seeding the
subject transaction's wtxid.

## Format contract {#format-contract}

- **Keys** — 32-byte binary wire-order wtxids. `String#encoding` must be
  `ASCII-8BIT`.
- **Values** — any truthy value counts as "already verified". The SDK writes
  `true`. `nil` or `false` values are treated as absent (the walk will visit
  those wtxids normally).

### Encoding foot-gun

`Hash#[]` uses `String#hash` + `String#eql?`, which are encoding-sensitive for
strings containing high-bit bytes. A wtxid re-encoded as UTF-8 (via JSON
round-trip, or accidental string interpolation into a UTF-8 buffer) will
silently miss the cache and cause a full walk. Persist wtxids as `ASCII-8BIT`
throughout.

### Converting a display-order hex txid

If you have a display-order hex txid string (from a block explorer, an ARC
response, etc.) rather than a wire-order binary wtxid, use:

```ruby
wtxid = BSV::Transaction::TransactionInput.wtxid_from_hex(hex_txid)
```

The SDK does not validate individual Hash keys — malformed keys degrade safely
to seed-misses (the wtxid won't match anything in the walk).

### Type validation

Passing a non-`Hash` value (e.g. an `Array` or a `Set`) raises `ArgumentError`.
`Set` is explicitly rejected — an earlier iteration of this feature accepted
`Set`, but the bidirectional shape requires the caller to be able to read
values back, so `Hash` is now the only accepted collection type.

## Caller responsibilities {#caller-responsibilities}

- **Correctness.** The SDK cannot verify that a seeded wtxid actually passed
  script validation or has a real chain anchor. If the cache is wrong,
  `verify` returns `true` for a subtree that has not actually been verified.
  The network is the backstop — ARC and miners will reject a broadcast whose
  inputs are invalid — but the wallet may have committed to downstream state
  (returning `true` to a UI, marking a UTXO spendable) in the interim.

- **Anchoring policy is the caller's.** `verify` accepts a leaf as verified
  on script alone — `unlocking_script` + `source_locking_script` +
  `source_satoshis` — so an input with `source_transaction: nil` can pass
  and be written to the cache without ever reaching a merkle proof. If your
  policy requires every persisted verdict to bottom out in a merkle-anchored
  ancestor (i.e. SPV-proven), enforce that upstream: reject the input before
  calling `verify`, or gate the cache write on the walk terminating in a
  proof. In BEEF-shaped ingress this happens implicitly — an unresolved leaf
  has nil source data and raises `VerificationError(:missing_source)`
  — but the SDK itself makes no anchoring guarantee. See
  [#914](https://github.com/sgbett/bsv-ruby-sdk/issues/914) for the
  discussion that landed on this boundary.

- **Staleness invalidation.** If a transaction's script validity or chain
  anchor could have changed (chain reorganisation, consensus flag update),
  remove its wtxid from the cache before calling `verify`. The seed treats the
  wtxid as fully trusted — merkle proofs are not re-verified for seeded
  entries.

- **Consensus-flag invalidation.** Cached wtxids are pinned to the consensus
  flags under which they were originally verified. Invalidate the cache when
  consensus flags change.

- **Chain-tracker binding.** A cache is bound to the `chain_tracker` (and its
  network and consensus context) that populated it. The SDK records only *that*
  a wtxid was verified, not *which* tracker proved it, so a seeded wtxid
  short-circuits verification regardless of the `chain_tracker` passed to a
  later `verify`. Do not reuse a cache across different trackers or networks —
  a subtree proven under a weak or attacker-influenced tracker would then be
  trusted by an authoritative one.

- **Thread-safety.** Do not mutate the `Hash` from another thread while
  `verify` is running. The SDK does **not** freeze the caller's Hash (it needs
  to write to it) and does not defend against concurrent mutation.

- **No isolated reads.** If `verified:` is `nil` (or omitted), the SDK uses an
  internal Hash the caller cannot access — you get no post-read. Pass an
  empty Hash if you want the SDK to accumulate walked wtxids you can read.

## Compatibility

- Backwards-compatible with the default `verified: nil` — every existing caller
  path is byte-identical to the pre-kwarg behaviour.

- **Not** backwards-compatible with an intermediate design that accepted `Set`
  (present in PR #912 before the amendment). If you tracked this at that
  stage, migrate: `Set.new(cache.keys)` → `cache` (drop the Set wrap; hand the
  Hash directly).
