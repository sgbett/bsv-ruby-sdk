---
title: Overview
nav_order: 1
parent: Network
---

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

The SDK ships six protocols:

| Protocol | Commands | Used by |
|----------|----------|---------|
| `Protocols::ARC` | broadcast, broadcast_many, get_tx_status, get_policy, health | TAAL |
| `Protocols::Arcade` | broadcast, get_tx_status, health | GorillaPool |
| `Protocols::WoCREST` | get_tx, get_utxos, is_utxo, current_height, valid_root, get_merkle_path, + 20 more | WhatsOnChain |
| `Protocols::Chaintracks` | get_block_header, current_height | (follow-up: see #778) |
| `Protocols::Ordinals` | get_tx, get_merkle_path | GorillaPool |
| `Protocols::TAALBinary` | broadcast | TAAL |

#### ARC vs Arcade

`Protocols::ARC` and `Protocols::Arcade` are distinct protocols backed by different
open-source implementations:

- **ARC** (`bitcoin-sv/arc`) — run by TAAL at `arc.taal.com`. Accepts EF-format
  transactions, returns `{"txid": "...", "txStatus": "SEEN_ON_NETWORK", ...}`, and
  exposes `/v1/policy` for live fee-rate queries. Full status taxonomy:
  `RECEIVED`, `SEEN_ON_NETWORK`, `MINED`, `REJECTED`, `DOUBLE_SPEND_ATTEMPTED`,
  `INVALID`, `MALFORMED`, `MINED_IN_STALE_BLOCK`.

- **Arcade** (`bsv-blockchain/arcade`) — run by GorillaPool at
  `arcade.gorillapool.io`. The Teranode-era reimplementation. Path prefix is `/`
  (not `/v1/`). Broadcast success returns `{"status": "submitted"}` (not `txid`).
  Status taxonomy: `RECEIVED`, `SEEN_ON_NETWORK`, `SEEN_ON_MULTIPLE_NODES`,
  `MINED`, `IMMUTABLE`, `REJECTED` — narrower than ARC. No `/v1/policy` endpoint.

Both services document some of the same header names (`X-CallbackUrl`,
`X-CallbackToken`, `X-SkipFeeValidation`, `X-SkipScriptValidation`), but their
request paths, response body shapes, and status taxonomies diverge enough that they
must be treated as distinct protocols. Response parsing is not shared.

**Important:** Arcade's `:get_tx_status` only tracks transactions that were
submitted through that Arcade instance. It returns 404 for arbitrary txids, even
known-mined ones. Use TAAL ARC or WhatsOnChain for general blockchain queries.

GorillaPool's chaintracks_server is a separate service on a separate port — it is
not wired in the current `Providers::GorillaPool` registration. See issue #778 for
the follow-up.

### Providers

Providers are configuration — a named entity (company/service) that hosts one or more
protocols at specific URLs. The SDK ships three provider defaults:

```ruby
BSV::Network::Providers::GorillaPool.default   # Arcade + Ordinals + JungleBus
BSV::Network::Providers::WhatsOnChain.default   # WoCREST (30+ endpoints)
BSV::Network::Providers::TAAL.default           # ARC + TAALBinary
```

Each provider composes protocol instances with concrete URLs and credentials. When you
call `.default`, you get a ready-to-use provider pointed at the mainnet endpoints.
Pass `testnet: true` for testnet.

#### Auth and Rate Limit Metadata

Providers carry `auth` and `rate_limit` as metadata — they describe what credentials
the provider is configured with and what request rate is appropriate. The SDK does not
enforce rate limiting itself; that is a consumer concern.

```ruby
provider = BSV::Network::Providers::WhatsOnChain.mainnet(
  auth: { api_key: 'my-key' },
  rate_limit: 10
)

provider.authenticated?   # => true
provider.auth             # => { api_key: 'my-key' }
provider.rate_limit       # => 10
```

Without credentials:

```ruby
provider = BSV::Network::Providers::GorillaPool.default
provider.authenticated?   # => false
provider.auth             # => :none
provider.rate_limit       # => 3  (GorillaPool default)
```

The `rate_limit` value is requests per second. Each provider factory sets a
`DEFAULT_RATE_LIMIT` constant for unauthenticated use:

| Provider | `DEFAULT_RATE_LIMIT` | Notes |
|----------|---------------------|-------|
| `WhatsOnChain` | 3 | Public tier limit |
| `GorillaPool` | 3 | Public tier limit |
| `TAAL` | `nil` | Depends on subscription tier |

## SDK Entry Points

The SDK exposes three stable entry points for the network layer:

```ruby
# Broadcasting — via a provider (GorillaPool Arcade by default)
provider = BSV::Network::Providers::GorillaPool.default
result = provider.call(:broadcast, tx)
puts result.data['txid'] if result.http_success?

# Chain data — via the WoCREST provider
woc = BSV::Network::Providers::WhatsOnChain.default
result = woc.call(:get_utxos, address)
result.data.each { |u| puts "#{u['tx_hash']}:#{u['tx_pos']}" } if result.http_success?

# SPV verification — ChainTrackers::WhatsOnChain wraps WoCREST with a higher-level API
tracker = BSV::Transaction::ChainTrackers::WhatsOnChain.new(network: :main)
tracker.valid_root_for_height?(merkle_root, height)
```

The protocol layer returns `BSV::Network::ProtocolResponse` objects — check
`result.http_success?` before reading `result.data`.

> **Note on `ChainTrackers`:** `ChainTrackers::WhatsOnChain` is a legacy facade that
> wraps WhatsOnChain's chain-info endpoint directly. It continues to work unchanged.
> `ChainTrackers::Chaintracks` (the former Arcade Chaintracks wrapper) has been removed
> and replaced by the provider-routed porcelain described below. If you were using
> `ChainTrackers::Chaintracks` or `ChainTrackers.default`, migrate to
> `ChainTracker.default`.

## Provider-routed Semantic Operations

The Network module distinguishes **wire protocols** (Arcade, ARC, JungleBus, WoCREST,
Ordinals, TAALBinary) from **semantic capabilities** (verify merkle root, broadcast tx,
fetch fee policy). A wire protocol knows how to speak to one class of service. A
semantic operation — like "what is the current chain height?" — may be satisfiable by
several different wire protocols depending on which provider is in use.

`BSV::Transaction::ChainTracker` is the first example of this pattern. Rather than
binding to a single wire protocol (Chaintracks, WoCREST, or otherwise), it accepts any
`Provider` and routes `:get_block_header` and `:current_height` through that provider's
registered protocols:

```ruby
# Default: GorillaPool provider (JungleBus for :current_height,
# Arcade for :get_block_header). No credentials required.
tracker = BSV::Transaction::ChainTracker.default

# Testnet:
tracker = BSV::Transaction::ChainTracker.default(testnet: true)

# Custom provider — any provider that exposes :get_block_header and :current_height
own = BSV::Network::Provider.new('local') do |p|
  p.protocol BSV::Network::Protocols::Chaintracks, base_url: 'http://my-chaintracks-server'
end
tracker = BSV::Transaction::ChainTracker.new(own)
```

The same pattern will extend to broadcast, transaction fetch, and fee model in future —
each becoming a porcelain that routes through `Provider#call` rather than committing
to one wire format at construction time.

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
public contract is unchanged. New porcelain classes (`ChainTracker`) route through
a `Provider` rather than a fixed protocol, enabling provider substitution at
construction time.

## How It Fits Together

```
Application code
    ↓ calls
Facades / Porcelain (ARC, WhatsOnChain, ChainTrackers::WhatsOnChain, ChainTracker)
    ↓ delegates to
Protocols (ARC, WoCREST, Chaintracks, JungleBus, ...)
    ↓ hosted by
Providers (GorillaPool, WhatsOnChain, TAAL)
    ↓ dispatches via
HTTP (Net::HTTP or injectable client)
```

See [Examples](examples.md) for concrete usage patterns.
