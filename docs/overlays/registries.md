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

The SDK ships both the **read paths** (`resolve_basket`, `resolve_protocol`,
`resolve_certificate`) and the **write paths** (`register_definition`,
`update_definition`, `revoke_definition`). Write paths require a BRC-100 wallet
to create and sign transactions.

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

## Write paths

`Registry::Client` includes write paths on the same class. These methods need a BRC-100-compatible wallet (e.g. `bsv-wallet`'s `Wallet::Client`) because they create and sign on-chain transactions. Passing `wallet: nil` and calling a write path raises `NoMethodError`.

### `register_definition`

Publishes a new definition as a PushDrop UTXO and broadcasts it to the appropriate overlay topic:

```ruby
require 'bsv-sdk'

client = BSV::Registry::Client.new(wallet: my_wallet, originator: 'myapp.example.com')

data = BSV::Registry::BasketDefinitionData.new(
  basket_id:         'my-tokens',
  name:              'My Token Collection',
  icon_url:          'https://example.com/icon.png',
  description:       'Stores my custom tokens',
  documentation_url: 'https://example.com/docs'
)

result = client.register_definition(BSV::Registry::DefinitionType::BASKET, data)
# result is a BSV::Overlay::OverlayBroadcastResult
# raises BSV::Overlay::OverlayError (or a subclass) if the broadcast fails
```

Protocol and certificate definitions work the same way — swap the type constant and the data class:

```ruby
# Protocol definition
proto_data = BSV::Registry::ProtocolDefinitionData.new(
  protocol_id:       [1, 'my-protocol'],
  name:              'My Protocol',
  icon_url:          'https://example.com/icon.png',
  description:       'What this protocol does',
  documentation_url: 'https://example.com/spec'
)
client.register_definition(BSV::Registry::DefinitionType::PROTOCOL, proto_data)

# Certificate type definition
cert_data = BSV::Registry::CertificateDefinitionData.new(
  type:              'aW1hZ2U=',   # Base64 type identifier
  name:              'Profile',
  icon_url:          'https://example.com/cert.png',
  description:       'Basic identity profile',
  documentation_url: 'https://example.com/cert-spec',
  fields:            {}
)
client.register_definition(BSV::Registry::DefinitionType::CERTIFICATE, cert_data)
```

### `update_definition`

Replaces an existing definition by spending its UTXO and publishing a new one. The update is two sequential operations (revoke then register) — not atomic. If registration fails after revocation, the old definition will have been removed without replacement.

```ruby
# Find the definition you want to update
existing = client.list_own_registry_entries(BSV::Registry::DefinitionType::BASKET).first

updated_data = BSV::Registry::BasketDefinitionData.new(
  basket_id:         existing.definition_data.basket_id,
  name:              'My Token Collection (v2)',
  icon_url:          existing.definition_data.icon_url,
  description:       'Updated description',
  documentation_url: existing.definition_data.documentation_url
)

client.update_definition(existing, updated_data)
# The existing UTXO is spent; a new one is published with the updated data
```

### `revoke_definition`

Spends the definition UTXO to remove it from overlay lookup responses. Only definitions belonging to the current wallet's identity key can be revoked — `revoke_definition` raises `RuntimeError` if the registry operator pubkey does not match the wallet's identity key.

```ruby
my_entries = client.list_own_registry_entries(BSV::Registry::DefinitionType::BASKET)
to_revoke  = my_entries.find { |d| d.definition_data.basket_id == 'my-tokens' }

client.revoke_definition(to_revoke)
# The UTXO is spent; the definition disappears from resolve responses
```

### `list_own_registry_entries`

Queries the wallet for spendable outputs in the registry basket and returns them as `RegisteredDefinition` objects:

```ruby
my_baskets = client.list_own_registry_entries(BSV::Registry::DefinitionType::BASKET)
my_baskets.each { |d| puts d.definition_data.name }
```

If you are only reading, inject a `resolver:` and pass `wallet: nil` — the constructor accepts it and the typed resolve methods work without a wallet.

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
- [SDK reference: Script](../sdk/script.md) — see the `PushDropTemplate` section for the locking script template underlying every registry definition (section added by #899)
