# Network Architecture

The SDK's network layer separates **what** can be done from **who** does it and **how** the
wire format works. This separation means you can swap providers, add new endpoints, or
change protocols without touching application code.

## Three Layers

### Commands

Commands are the SDK's vocabulary — named operations like `:broadcast`, `:get_tx`, or
`:is_utxo`. They represent immutable BSV concepts: "broadcast a transaction", "fetch a
raw transaction", "check whether a UTXO is spent". Commands are defined once in the SDK
and don't change when providers or protocols change.

### Protocols

Protocols define the wire format for groups of commands. Each protocol is a Ruby class
with a declarative DSL that maps command names to HTTP endpoints:

```ruby
class BSV::Network::Protocols::ARC < BSV::Network::Protocol
  endpoint :broadcast,     :post, '/v1/tx'
  endpoint :get_tx_status, :get,  '/v1/tx/{txid}', response: :json
  endpoint :get_policy,    :get,  '/v1/policy',    response: :json
end
```

A protocol knows nothing about URLs or credentials — it only knows path templates,
HTTP methods, and response formats. Complex commands use escape hatches (`call_<name>`
methods) for custom logic like the ARC broadcast's Extended Format negotiation.

The SDK ships five protocols:

| Protocol | Commands | Used by |
|----------|----------|---------|
| `Protocols::ARC` | broadcast, broadcast_many, get_tx_status, get_policy, health | GorillaPool, TAAL |
| `Protocols::WoCREST` | get_tx, get_utxos, is_utxo, current_height, valid_root, get_merkle_path, + 20 more | WhatsOnChain |
| `Protocols::Chaintracks` | get_block_header, current_height | GorillaPool |
| `Protocols::Ordinals` | get_tx, get_merkle_path | GorillaPool |
| `Protocols::TAALBinary` | broadcast | TAAL |

### Providers

Providers are configuration — a named entity (company/service) that hosts one or more
protocols at specific URLs. The SDK ships three provider defaults:

```ruby
BSV::Network::Providers::GorillaPool.default   # ARC + Chaintracks + Ordinals
BSV::Network::Providers::WhatsOnChain.default   # WoCREST (30+ endpoints)
BSV::Network::Providers::TAAL.default           # ARC + TAALBinary
```

Each provider composes protocol instances with concrete URLs and credentials. When you
call `.default`, you get a ready-to-use provider pointed at the mainnet endpoints.
Pass `testnet: true` for testnet.

## SDK Facades

For convenience, the SDK provides facade classes that preserve the familiar API from
the TypeScript and Go reference SDKs:

```ruby
# Broadcasting (ARC protocol via GorillaPool)
arc = BSV::Network::ARC.default
response = arc.broadcast(tx)

# Chain data (WoCREST protocol via WhatsOnChain)
woc = BSV::Network::WhatsOnChain.default
utxos = woc.fetch_utxos(address)
tx = woc.fetch_transaction(txid)

# SPV verification (WoCREST protocol via WhatsOnChain)
tracker = BSV::Transaction::ChainTrackers::WhatsOnChain.default
tracker.valid_root_for_height?(merkle_root, height)
```

Facades are **contract translators** — they delegate to the protocol layer internally
but return domain objects (UTXO, Transaction, BroadcastResponse) and raise exceptions
(BroadcastError, ChainProviderError) that consumers expect. The protocol layer speaks
Result types (Success, Error, NotFound); facades translate these into the imperative
contracts that application code uses.

## Design Principles

**Protocols are pure wire format.** A protocol class contains no URLs, no credentials,
and no provider-specific logic. It knows how to turn a command into an HTTP request
and normalise the response. The same ARC protocol class works for GorillaPool, TAAL,
or any future ARC-compatible endpoint.

**Providers are configuration.** A provider is a named bundle of protocol instances
with URLs and credentials. Adding a new provider means creating a new configuration —
no code changes to protocols or facades.

**URLs live in one place.** Provider defaults are the single source of truth for
endpoint URLs. No magic strings in protocols, facades, or application code.

**Facades preserve the public API.** `ARC.default`, `WhatsOnChain.new`, and
`ChainTrackers::WhatsOnChain.new` continue to work as they always have. The internal
implementation changed from imperative HTTP code to protocol delegation, but the
public contract is unchanged.

## How It Fits Together

```
Application code
    ↓ calls
Facades (ARC, WhatsOnChain, ChainTrackers)
    ↓ delegates to
Protocols (ARC, WoCREST, Chaintracks, ...)
    ↓ hosted by
Providers (GorillaPool, WhatsOnChain, TAAL)
    ↓ dispatches via
HTTP (Net::HTTP or injectable client)
```

See [Examples](examples.md) for concrete usage patterns.
