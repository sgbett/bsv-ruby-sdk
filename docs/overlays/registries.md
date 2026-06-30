---
title: Registries
nav_order: 4
parent: Overlay services
---

# Registries

The registry overlay maps human-readable names to canonical on-chain
definitions for three kinds of thing:

- **Baskets** — wallet output groupings (think "asset categories").
- **Protocols** — application protocol IDs used across BRC-43-aware wallets.
- **Certificate types** — schemas for BRC-52 identity certificates.

Each definition is a PushDrop UTXO signed by the *registry operator* —
typically the entity who owns the namespace. Anyone can publish a
definition; clients decide which operators they trust by passing
`registry_operators` filters in their queries.

The SDK ships the **read paths** (`resolve_basket`, `resolve_protocol`,
`resolve_certificate`). Publishing, updating, and revoking definitions
need a wallet and live in `bsv-wallet`.

## Why it exists

Wallets and apps need to talk about the same things by name:

- "Show me everything in the *ordinals* basket."
- "I'm signing with the *p2p messaging* protocol."
- "Verify this *identity profile* certificate."

Without a registry, every app invents its own ID and the wallet UI can't
tell `ordinals` from `ordinals-v2` from `ordinalz`. The registry overlay
gives each name a verifiable canonical definition — title, description,
icon URL, documentation link — so wallet UIs can show consistent metadata
across apps and the user can audit what they're consenting to.

## The three overlays

Each definition type runs on its own topic/lookup-service pair:

| Type | Topic | Lookup service | BRC-43 protocol ID |
|---|---|---|---|
| Basket | `tm_basketmap` | `ls_basketmap` | `[1, 'basketmap']` |
| Protocol | `tm_protomap` | `ls_protomap` | `[1, 'protomap']` |
| Certificate | `tm_certmap` | `ls_certmap` | `[1, 'certmap']` |

Naming follows [BRC-87](https://hub.bsvblockchain.org/brc/overlays/0087)'s
convention. Splitting the three types across separate overlays means a
node can choose to index only the kinds it cares about.

## What the SDK provides

```ruby
require 'bsv-sdk'

# Resolver-only construction — inject a resolver directly so no wallet is needed.
# Without resolver:, the client calls wallet.get_network to build one, which
# will raise NoMethodError if wallet: is nil.
resolver = BSV::Overlay::LookupResolver.new(network_preset: :mainnet)
client = BSV::Registry::Client.new(wallet: nil, resolver: resolver)

# Resolve baskets by id, name, or both
baskets = client.resolve_basket(basket_id: 'ordinals')

# Resolve protocols (BRC-43 [security_level, name] format)
protocols = client.resolve_protocol(protocol_id: [1, 'p2p messaging'])

# Resolve certificate types
certs = client.resolve_certificate(type: 'identity-v1')
```

Each method returns `Array<BSV::Registry::RegisteredDefinition>`. A
definition exposes the type-specific data via `definition_data`, plus
on-chain fields (`txid`, `output_index`, `satoshis`, `locking_script`,
`beef`) so you can verify authenticity:

```ruby
basket = baskets.first
basket.definition_data.basket_id           # => "ordinals"
basket.definition_data.name                # => "Ordinals"
basket.definition_data.icon_url            # => "https://example.com/ord.png"
basket.definition_data.description         # => "..."
basket.definition_data.registry_operator   # => pubkey hex of the publisher
basket.satoshis                            # => 1
basket.txid                                # => display-order txid
basket.output_index                        # => 0
basket.beef                                # => raw BEEF bytes (String); parse with BSV::Transaction::Beef.from_binary
```

### Trust model — filter by operator

The overlay returns *every* definition matching your query, regardless of
who published it. If you only trust certain operators, filter the
results client-side or pass `registry_operators:` so the overlay
pre-filters:

```ruby
client.resolve_basket(
  basket_id: 'ordinals',
  registry_operators: ['02a1b2c3...', '03d4e5f6...']
)
```

`resolve_basket`/`_protocol`/`_certificate` are thin typed wrappers
around the general `resolve(type, query)` method — kept for parity
with the typed API in the TypeScript, Go, and Python SDKs.

See [SDK reference: Ecosystem Clients](../sdk/ecosystem-clients.md) for
the full method surface.

## What the wallet provides

`Registry::Client` accepts a `wallet:` because its **write paths** are
on the same class:

- `register_definition(type, data)` — publish a new definition (broadcast
  to the corresponding `tm_*` topic).
- `update_definition(...)` — spend the existing UTXO and publish a new
  version.
- `revoke_definition(...)` — spend the UTXO to take the definition out of
  circulation.
- `list_own_registry_entries(type)` — query the wallet for definitions
  *this* identity has published.

Those methods need a BRC-100 wallet because they create-and-sign new
transactions. The Ruby SDK's `Client` requires one for those — pass any
BRC-100-compatible wallet (typically `bsv-wallet`'s `Wallet::Client`).

If you're only reading, you can pass `wallet: nil` and use only the
typed resolve methods. The constructor accepts it.

## Edge cases worth knowing

- **Multiple definitions can share a name.** The overlay doesn't dedupe.
  If two operators both register `basket_id: 'ordinals'`, you'll get two
  results and have to choose based on who you trust.
- **Empty queries are valid.** `client.resolve_basket()` returns every
  basket definition the overlay knows about. Useful for discovery; bad
  for performance unless you intend to scan.
- **Updates don't dedupe in history.** `update_definition` spends the old
  UTXO and creates a new one — readers see only the new state, but the
  history is walkable through Historian if you want to display
  provenance.
- **Revocation is a spend.** A revoked definition simply doesn't appear
  in lookup responses (the underlying UTXO is spent and no longer
  topical).

## References

- [BRC-87](https://hub.bsvblockchain.org/brc/overlays/0087) — overlay
  naming convention (where the `tm_*` / `ls_*` names come from)
- [BRC-43](https://hub.bsvblockchain.org/brc/key-derivation/0043) —
  protocol ID format (`[security_level, name]`)
- Go: [`registry/methods.go`](https://github.com/bsv-blockchain/go-sdk/blob/master/registry/methods.go)
- Python: [`bsv/registry/client.py`](https://github.com/bsv-blockchain/py-sdk/blob/master/bsv/registry/client.py)
- [SDK reference: Ecosystem Clients](../sdk/ecosystem-clients.md)
