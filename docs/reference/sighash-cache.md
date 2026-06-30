---
title: Sighash & Wire Cache
nav_order: 6
parent: Reference
---

# Sighash & Wire Cache

`Transaction::Tx` memoises the bytes and digests that BIP-143 sighash verification reads
many times across a transaction's inputs. The cache is a five-layer
Russian-doll structure; correct cache invalidation is the security control
that makes memoisation safe — without it, signing or verifying could read
stale state and produce silently invalid signatures.

## Cache layers

```
L3 — sighash component hashes      hash_prevouts: 32 B ivar
                                   hash_sequence: 32 B ivar
                                   hash_outputs_all: 32 B ivar
                                   hash_outputs_per_index: Hash{idx => 32 B}
L2 — wire format                   Tx#to_binary, Tx#wtxid (32 B)
L1 — per-struct binaries           TransactionInput#outpoint_binary,
                                   TransactionInput#to_binary,
                                   TransactionOutput#to_binary
```

Each layer composes from the layer below; invalidating an L1 binary
cascades to L2 and L3 via the owning `Transaction::Tx`'s slice invalidators.

## Invalidation contract {#invalidation-contract}

| Mutation                                    | Invalidates                                      |
|---------------------------------------------|--------------------------------------------------|
| `Transaction::Tx#add_input` / `#add_output` | all cache layers                                 |
| `TransactionInput#sequence=`                | `hash_sequence`, L1 `to_binary`, L2              |
| `TransactionInput#unlocking_script=`        | L1 `to_binary`, L2 (NOT sighash components)      |
| `TransactionOutput#satoshis=`               | `hash_outputs_*`, L1 `to_binary`, L2             |
| `TransactionOutput#locking_script=`         | `hash_outputs_*`, L1 `to_binary`, L2             |
| Direct `tx.inputs <<` / `pop`               | undefined — call `invalidate_caches`             |
| `Transaction::Tx#invalidate_caches`         | everything                                       |

`unlocking_script=` deliberately does not invalidate sighash components
because the unlocking script is not part of the BIP-143 preimage.

## One owner per input/output {#one-owner}

An input or output may belong to one `Transaction::Tx` at a time.
`Transaction::Tx#add_input` and `#add_output` set a private `@owning_tx`
backref; adding the same input or output to a *different* `Transaction::Tx`
raises `ArgumentError`. Sharing across `Transaction::Tx` instances is
anti-idiomatic and would silently corrupt the cache. Construct a fresh
`TransactionInput` or `TransactionOutput` per `Transaction::Tx`; the struct
has no signing state until you bind it.

Re-adding the same input or output to the *same* `Transaction::Tx` is
idempotent — the backref is already correct.

## Escape hatch {#escape-hatch}

If you need to mutate `tx.inputs` or `tx.outputs` directly (e.g. through
array methods that bypass the documented setter surface), call
`Transaction::Tx#invalidate_caches` afterward. The method clears every cache
layer and returns `self` for chaining.

```ruby
tx.inputs.pop                  # bypasses the documented setter surface
tx.invalidate_caches           # clears all cache layers
tx.verify(...)                 # now safe
```

In normal use you should never need to call it — the documented setters
(`input.sequence=`, `output.satoshis=`, etc.) and `Transaction::Tx#add_input` /
`#add_output` invalidate the right slices automatically.

## "Build → sign/verify" idiom

Construct the transaction (set inputs, outputs, source data), then sign
or verify. Avoid mutating inputs/outputs after the first signing or
verification call unless you have a specific reason — the documented
setters handle it correctly but you pay a recompute cost that buys you
nothing in typical flows.

## Thread-safety

`Transaction::Tx` is not declared thread-safe. The cache makes this stricter:
concurrent reads on the same `Transaction::Tx` instance from multiple threads
may observe partially-published ivars on JRuby and TruffleRuby (CRuby is
safer due to the GVL, but still not guaranteed). If you need to share a
`Transaction::Tx` across threads, serialise access externally.
