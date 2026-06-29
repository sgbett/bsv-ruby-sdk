---
title: Historian
nav_order: 2
parent: Overlay services
---

# Historian

`BSV::Overlay::Historian` is a generic walker over a transaction's input
ancestry. Given a starting transaction and a callable that knows how to
interpret one output, it returns the chronological sequence of all the
interpreter's values across the whole back-history.

It isn't itself an overlay — it's a tool you use to make sense of state
that overlays surface.

## Why it exists

Many overlay-backed application states are *mutable*: a KVStore key has a
current value but also a history of prior values; an identity certificate
may be re-issued; a registry definition can be updated. Each change is a
new transaction that spends the previous state UTXO.

So the *current* state is a single UTXO, but the *history* is the chain of
UTXOs you can walk by following each transaction's inputs back through
their source transactions.

Historian is the generic walker for that chain. It doesn't know what a
KVStore entry looks like or what an identity certificate is — that
knowledge lives in an *interpreter*. Historian just walks; the
interpreter decodes.

## The interpreter contract

An interpreter is any callable matching:

```ruby
interpreter.call(tx, output_index, ctx) #=> value or nil
```

- `tx` is a `BSV::Transaction::Tx`.
- `output_index` is the output Historian is asking about.
- `ctx` is whatever you passed to `build_history` — usually a hash like
  `{ key: 'foo', protocol_id: [1, 'kvstore'] }`.
- Return the typed value if this output matches your interest, or `nil` to
  skip it.

`nil` is the *only* skip signal: `false`, `""`, and `0` are all valid
history entries and will be included.

Anything you raise inside the interpreter is silently caught by Historian
and treated as a skip — your interpreter should never need to rescue for
defensive reasons.

## Getting started — a tiny interpreter

```ruby
require 'bsv-sdk'

# Match outputs that have an OP_RETURN containing a 'note:' push and
# return whatever follows as the value. Script#op_return_data returns
# Array<String> — one element per push — so iterate.
NoteInterpreter = ->(tx, idx, _ctx) {
  out    = tx.outputs[idx]
  pushes = out.locking_script.op_return_data
  marker = pushes&.find { |p| p.start_with?('note:') }
  marker&.slice(5..)
}

historian = BSV::Overlay::Historian.new(NoteInterpreter)
notes     = historian.build_history(some_tx)
# => ["first note", "second note", "third note"]   # oldest first
```

The same interpreter pattern is used internally by `KVStore::Global` when
you call `get(query, history: true)` — it walks the history of a key
through `KVStore::Interpreter`. See
[`docs/overlays/kvstore.md`](kvstore.md) for that path.

## Caching

For applications that repeatedly walk the same long history (UI rendering,
audit reports), pass any `[]/[]=`-responder as a cache:

```ruby
historian = BSV::Overlay::Historian.new(
  BSV::KVStore::Interpreter,
  history_cache: {},
  interpreter_version: 'v1'
)

historian.build_history(tx, ctx)  # cold — walks ancestry
historian.build_history(tx, ctx)  # hot — returns cached duplicate
```

The cache key is `"#{interpreter_version}|#{dtxid_hex}|#{ctx_key}"`. Bump
`interpreter_version` to invalidate the cache when your interpreter
changes meaning. `ctx_key` defaults to `context.to_s`; pass a
`ctx_key_fn:` callable if your context doesn't serialise sensibly that
way.

Cached arrays are stored frozen; each retrieval returns a `dup` so
consumer mutation can't poison the cache.

## When *not* to use Historian

Historian walks `input.source_transaction` — so your starting transaction
must have its input ancestry populated (typically via BEEF). If you only
have a TXID, you can't walk anything: fetch the ancestry first via your
chain tracker or overlay.

It's also strictly sequential: a 500-deep history walks 500 transactions
serially. For very deep ancestries, consider caching incremental results
or building a domain-specific index over the overlay's lookup service
instead.

## Edge cases worth knowing

- **Cycles.** Historian tracks a visited set keyed by `wtxid` (binary).
  Pathological inputs that try to point back at an ancestor are visited
  once and then ignored.
- **Missing source transactions.** Inputs without `source_transaction`
  populated are skipped silently (debug-logged if you pass `debug: true`).
- **Interpreter exceptions.** Per-output rescue inside `traverse` — your
  interpreter can throw anything, and traversal continues.
- **Deep stacks.** Ancestry is walked recursively, so the practical limit
  is Ruby's stack depth. We follow the TS reference here; converting to
  an iterative worklist is a future enhancement if real-world ancestries
  ever hit that wall.

## References

- TypeScript: [`Historian.ts`](https://github.com/bsv-blockchain/ts-stack/blob/main/packages/sdk/src/overlay-tools/Historian.ts)
- Python: [`bsv/overlay_tools/historian.py`](https://github.com/bsv-blockchain/py-sdk/blob/master/bsv/overlay_tools/historian.py)
- [SDK reference: Ecosystem Clients](../sdk/ecosystem-clients.md)
- [KVStore overlay](kvstore.md) — the most common Historian consumer
