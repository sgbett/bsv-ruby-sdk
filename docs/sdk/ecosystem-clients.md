# Ecosystem Clients

The SDK ships several overlay-aware client modules that work alongside `BSV::Registry::Client`
to query and interact with protocol-specific overlay services: the Registry for discovering
known baskets, protocols, and certificate types; the Historian for reconstructing the history
of any PushDrop token; the KVStore for reading the global key-value store; and the Storage
downloader for fetching UHRP-addressed content.

For full details, see the individual pages:

- [Storage (Utils + Downloader)](storage.md)
- [KVStore (Global + Interpreter)](kvstore.md)
- [Registry Client](../overlays/registries.md) *(typed resolves are covered below)*

## Registry::Client — typed resolves

`BSV::Registry::Client` provides three convenience methods that correspond to the Go SDK's
`ResolveBasket`, `ResolveProtocol`, and `ResolveCertificate`:

```ruby
require 'bsv-sdk'

client = BSV::Registry::Client.new(wallet: my_wallet)

# Resolve basket definitions
baskets = client.resolve_basket(basket_id: 'tokens.1sat')
baskets.first.definition_data.name          # => "1Sat Ordinals"
baskets.first.definition_data.icon_url      # => "https://..."

# Resolve protocol definitions — protocol_id is a two-element BRC-43 array
protocols = client.resolve_protocol(protocol_id: [1, 'my-app'])
protocols.first.definition_data.description # => "Stores my application state"

# Resolve certificate type definitions
certs = client.resolve_certificate(name: 'Age Verification')
certs.first.definition_data.type            # => Base64 certificate type identifier

# No-argument form — returns all registered definitions of that type
all_baskets = client.resolve_basket
```

**Contract notes:**

- All three methods return `Array<RegisteredDefinition>`. An empty array means no matching
  definitions were found.
- `resolve_basket` / `resolve_protocol` / `resolve_certificate` are thin wrappers around
  `resolve(definition_type, query)` — use the lower-level method when you need to pass
  `registry_operators:` to filter by operator public key.
- Outputs that fail BEEF parsing or PushDrop decoding are silently skipped.

## Overlay::Historian

`Historian` traverses a transaction's input ancestry and returns a chronological list of
values decoded by an interpreter callable. It is protocol-agnostic — any callable that
accepts `(tx, output_index, ctx)` and returns a value or `nil` works.

```ruby
require 'bsv-sdk'

# Custom interpreter: extract OP_RETURN payloads from a specific app prefix
my_interpreter = ->(tx, output_index, _ctx) do
  script = tx.outputs[output_index]&.locking_script
  return nil unless script&.op_return?

  items = script.op_return_data
  return nil unless items&.first == 'myapp'.b

  items[1]&.force_encoding('UTF-8')
end

historian = BSV::Overlay::Historian.new(my_interpreter)
history   = historian.build_history(tx)
# => ["first-value", "second-value", "current-value"]  (oldest → newest)
```

**Contract notes:**

- Inputs must have `source_transaction` populated for traversal to follow ancestors.
  Use `BSV::Transaction::Beef` to load a fully-linked transaction graph.
- Each transaction is visited at most once; cycles are safe.
- `false`, `""`, and `0` are valid history entries and are included. Only `nil` is excluded.
- Pass `history_cache:` (any Hash-like object) to cache results across calls.
  Cache keys have the form `"#{interpreter_version}|#{dtxid_hex}|#{ctx_key}"`.
- Pass `debug: true` to emit traversal logging via `BSV.logger`.
