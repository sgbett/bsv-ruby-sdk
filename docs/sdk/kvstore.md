---
title: KVStore
nav_order: 7
parent: SDK
---

# KVStore

`BSV::KVStore::Global` is a read-only client for the global KVStore overlay service.
It queries the `ls_kvstore` lookup service, decodes and verifies PushDrop tokens, and
returns typed `Entry` objects. Set and remove operations require wallet writes and live
in the `bsv-wallet` gem.

## Querying entries

```ruby
require 'bsv-sdk'

kv = BSV::KVStore::Global.new(network_preset: :mainnet)

# Look up by key + protocol
entries = kv.get(
  key: 'user-preference',
  protocol_id: [1, 'my-app']
)
entry = entries.first
entry.key          # => "user-preference"
entry.value        # => "dark-mode"
entry.controller   # => "03a1b2c3..." (compressed pubkey hex)
entry.protocol_id  # => [1, "my-app"]
entry.tags         # => ["ui", "prefs"] or nil for old-format tokens

# Look up by controller (all keys belonging to an identity)
kv.get(controller: '03a1b2c3...')

# Look up by tags
kv.get(tags: ['ui'], tag_query_mode: 'any')

# Include the raw BEEF token for on-chain verification
entries = kv.get({ key: 'user-preference', protocol_id: [1, 'my-app'] }, include_token: true)
entries.first.token.dtxid        # => display-order txid hex
entries.first.token.output_index # => 0
```

**Contract notes:**

- `get` requires at least one selector (`key`, `controller`, `protocol_id`, or a non-empty
  `tags` array); it raises `ArgumentError` without one.
- `get` always returns an `Array`; use `.first` when you expect a single result.
- Outputs that fail BEEF parsing, field-count validation, or signature verification are
  silently skipped — the array may be shorter than the raw lookup result.
- Pass `lookup_resolver:` to inject a custom `BSV::Overlay::LookupResolver` for testing
  or pointing at a local network.

## KVStore::Interpreter (advanced)

`KVStore::Interpreter` implements the Historian interpreter contract and is used internally
by `Global` when `history: true` is passed to `get`. You can also use it directly with
`BSV::Overlay::Historian` to walk the ancestry of any KVStore-bearing transaction:

```ruby
historian = BSV::Overlay::Historian.new(BSV::KVStore::Interpreter)
history   = historian.build_history(tx, { key: 'user-preference', protocol_id: [1, 'my-app'] })
# => ["initial-value", "updated-value", "dark-mode"]  (oldest → newest)
```

The interpreter never raises — it returns `nil` for any output that does not match the
given `key` and `protocol_id`.
