---
title: KVStore
nav_order: 3
parent: Overlay services
---

# KVStore

The KVStore overlay is a signed key-value store backed by overlay-tracked
PushDrop UTXOs. Each entry is owned by a *controller* (a public key), tagged
with a *protocol ID*, and signed — so readers can verify both who set the
value and which application namespace it belongs to.

The SDK's `BSV::KVStore::Global` is the **read client**. The matching
write client (set, remove, double-spend retry) lives in `bsv-wallet`.

## Why it exists

Apps need cross-device, cross-app shared state on top of BSV without
running their own database — a username profile, a preference value, a
public configuration setting. Plain transactions can carry data but offer
no read API; a separate database breaks the "self-contained on BSV"
property apps want.

KVStore solves this by:

1. **Storing the entry as a PushDrop UTXO.** Fields encode the protocol ID,
   the key, the value, the controller pubkey, optional tags, and a
   signature over them all.
2. **Tracking the UTXO on the `tm_kvstore` topic.** Setting a new value
   spends the previous UTXO, so the overlay always knows which UTXO is the
   current entry for a given controller/key/protocol triple.
3. **Exposing reads through `ls_kvstore`.** Clients query by any
   combination of key, controller, protocol ID, or tags.

## What the SDK provides

### `BSV::KVStore::Global` — the read client

`#get(query)` always returns `Array<KVStore::Entry>` — even for
single-result selectors. Use `.first` if you expect one result.

```ruby
require 'bsv-sdk'

kv = BSV::KVStore::Global.new(network_preset: :mainnet)

# Look up by key alone — may return multiple controllers' entries
entries = kv.get({ key: 'display_name' })

# Narrow by controller pubkey hex
entries = kv.get({
  key:        'display_name',
  controller: '02a1b2c3...'
})

# Filter by protocol namespace
entries = kv.get({
  key:         'theme',
  protocol_id: [1, 'my-app-prefs']
})

# Inspect an entry
entry = entries.first
entry.key         # => "display_name"
entry.value       # => "Alice"
entry.controller  # => "02a1b2c3..."
entry.protocol_id # => [1, "babbage-profile"]
entry.tags        # => nil  (or an array on 6-field tokens)
```

At least one of `key`, `controller`, `protocol_id`, or non-empty `tags`
must be present — otherwise the call raises `ArgumentError`.

### Including the source token

Pass `include_token: true` to populate the underlying BEEF, dtxid, and
output index. Useful if you want to spend the entry from a wallet:

```ruby
entry = kv.get({ key: 'foo' }, include_token: true).first
entry.token.dtxid         # => display-order txid hex
entry.token.output_index  # => 0
entry.token.beef          # => BEEF object — verifiable, embeddable
entry.token.satoshis      # => 1
```

### Including history

Pass `history: true` and Historian walks the UTXO's ancestry, decoding each
previous version of the entry:

```ruby
entry = kv.get({ key: 'theme' }, history: true).first
entry.value    # => "dark"          (current)
entry.history  # => ["system", "light", "dark"]  (oldest first)
```

Internally this is `Overlay::Historian.new(KVStore::Interpreter).build_history`.
See [Historian](historian.md) for the underlying mechanic.

### `BSV::KVStore::Interpreter` — the decoder

`Interpreter.call(tx, output_index, ctx)` is the Historian callable for
KVStore PushDrop tokens. You normally don't call it directly — `Global`
wires it up — but it's exposed in case you want to plug it into your own
walker. The contract:

- Returns the UTF-8 value String on match.
- Returns `nil` for any mismatch, malformed field, signature failure, or
  encoding error.
- Never raises.

## Signature verification

Every entry returned by `Global#get` has been verified against the
controller's pubkey using `BSV::Wallet::ProtoWallet.verify_signature` —
the standard BRC-100 verification path. Entries that fail verification
are silently dropped, matching the TS SDK contract.

If you need stricter behaviour — e.g. logging dropped entries — pass your
own `proto_wallet:` to the `Global` constructor.

## What the wallet provides

[`bsv-wallet`](https://github.com/sgbett/bsv-wallet) ships `LocalKVStore` for **writes**:
`#set`, `#remove`, optimistic double-spend retry, and a key-locking layer
so concurrent writers from the same wallet don't race against each other.

The split is the same as everywhere else: reading needs only the public
overlay query; writing needs a wallet to fund the new UTXO and sign it.

## Edge cases worth knowing

- **Field-count compatibility.** Two on-the-wire formats are accepted:
  5-field legacy (no tags) and 6-field current (with tags). Anything else
  is silently skipped.
- **Selector validation.** Empty strings don't count as a selector. Pass
  `key: ''` and you'll get an `ArgumentError`.
- **No "single entry" overload.** Some other SDKs let you call
  `get(controller, key)` and get either an entry or `nil`. The Ruby SDK
  always returns Array — use `.first`.
- **Camel-case is handled.** The Ruby query takes snake_case keys
  (`protocol_id`, `tag_query_mode`). They're translated to the overlay's
  expected camelCase (`protocolID`, `tagQueryMode`) at the boundary.

## References

- TypeScript: [`GlobalKVStore.ts`](https://github.com/bsv-blockchain/ts-stack/blob/main/packages/sdk/src/kvstore/GlobalKVStore.ts) (canonical reference)
- [SDK reference: KVStore](../sdk/kvstore.md)
- [Historian overlay](historian.md) — used for the `history: true` path
- [BRC-100](https://hub.bsvblockchain.org/brc/wallet/0100) — wallet
  interface (`verify_signature`, `ProtoWallet`)
