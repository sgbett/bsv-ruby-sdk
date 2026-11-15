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

The SDK ships these protocols:

| Protocol | Commands | Used by |
|----------|----------|---------|
| `Protocols::ARC` | broadcast, broadcast_many, get_tx_status, get_policy, health | GorillaPool, TAAL |
| `Protocols::Arcade` | broadcast, get_tx_status, get_policy, health | BSVAssociation (opt-in) |
| `Protocols::WoCREST` | get_tx, get_utxos, is_utxo, current_height, valid_root, get_merkle_path, + 48 more (54 in all) | WhatsOnChain |
| `Protocols::Chaintracks` | get_block_header, current_height | (follow-up: see #778) |
| `Protocols::Ordinals` | get_tx, get_merkle_path, get_utxos, + 5 more (8 in all) | GorillaPool |
| `Protocols::JungleBus` | current_height, get_block_header, get_address_txs, + 3 more (6 in all) | GorillaPool |
| `Protocols::TAALBinary` | broadcast | TAAL |

The generated [protocol reference](protocols/index.md) lists every command.

#### ARC vs Arcade

`Protocols::Arcade` speaks to the BSV Broadcaster (formerly Arcade, `bsv-blockchain/broadcaster`), the Teranode-era service the BSV Association runs. `Protocols::ARC` speaks to classic ARC (`bitcoin-sv/arc`), which GorillaPool and TAAL run. As of BSV Broadcaster v0.21 the response bodies are ARC-compatible: a successful broadcast carries `txid`, `txStatus` and the other ARC fields, and both protocols treat a rejected status as a failure using ARC's rule. Arcade does not apply ARC's `extraInfo` orphan heuristic. What still differs is the request side:

- **Paths.** ARC lives under `/v1` (`/v1/tx`, `/v1/tx/{txid}`, `/v1/policy`); Arcade is at the root (`/tx`, `/tx/{txid}`, `/policy`). The BSV Broadcaster also serves `/v1/policy`, and `Protocols::Arcade` uses `/policy`.
- **Extended Format only.** Arcade raises `ArgumentError`, and sends nothing, for a transaction without source outputs or for a string that is not Extended Format. ARC falls back to plain hex.
- **Headers.** Arcade understands only `X-CallbackUrl`, `X-CallbackToken` and `X-FullStatusUpdates`. It has no skip-validation or wait-for headers, so the `skip_fee_validation:` and `skip_script_validation:` options are gone.
- **Errors.** Arcade errors are flat `{"error": "...", "reason": "..."}` objects, and a successful submission is HTTP 202, so `result.data['status']` is the integer `202`. On ARC, `data['status']` on an error is an ARC code. Neither is the string `'submitted'` that earlier Arcade responses carried; read `txStatus`.
- **Backpressure.** Arcade answers 429 and 503 with `Retry-After`; the response is a failed `ProtocolResponse` that is `retryable?`, and a numeric `Retry-After` is included in its `error_message`.

`get_tx_status` on ARC and Arcade validates its argument: anything other than a 64-character display-order hex txid raises `ArgumentError` and sends nothing. A reply that names a different txid from the one asked about is a failed `ProtocolResponse` (malformed reply), not a success.

**Transport failures.** Every transport failure except those that happen before anything is sent (DNS failure, open timeout, connection refused) sets an `error_message` ending "(the request may have reached the service)". After a failed broadcast with that message, the service may hold the transaction. Resubmit the identical transaction, or query its status; never rebuild it with different inputs, which would risk a double spend.

**Important:** status tracking is per instance, on both services. `:get_tx_status` only knows transactions that were submitted to that instance, and returns 404 for arbitrary txids, even known-mined ones. Use WhatsOnChain or JungleBus for general blockchain queries.

Nothing in the SDK defaults to the BSV Broadcaster. GorillaPool, as in the TypeScript and Python SDKs, broadcasts through classic ARC. Use `Providers::BSVAssociation` to opt in (see below).

GorillaPool's chaintracks_server is a separate service on a separate port — it is
not wired in the current `Providers::GorillaPool` registration. See issue #778 for
the follow-up.

### Providers

Providers are configuration — a named entity (company/service) that hosts one or more
protocols at specific URLs. The SDK ships these providers:

```ruby
BSV::Network::Providers::GorillaPool.default    # ARC + Ordinals + JungleBus
BSV::Network::Providers::WhatsOnChain.default   # WoCREST (30+ endpoints)
BSV::Network::Providers::TAAL.default           # ARC + TAALBinary (needs a key)
BSV::Network::Providers::BSVAssociation.default # BSV Broadcaster (Arcade), opt-in
```

Each provider composes protocol instances with concrete URLs and credentials. When you
call `.default`, you get a ready-to-use provider pointed at the mainnet endpoints.
Pass `testnet: true` for testnet.

`TAAL.default` needs a key: without one, TAAL's ARC answers 401 on everything except `/v1/policy`. `BSVAssociation` needs no key (anonymous use is rate-limited per IP address) and, like TAAL, no SDK default uses it: pick it deliberately.

A key given to a provider goes to every protocol it composes, so `GorillaPool.mainnet(auth: { bearer: 'token' })` sends it to the ARC, Ordinals and JungleBus hosts. Keys are never shared across providers.

#### Auth and Rate Limit Metadata

`inspect` and `to_s` on protocols (and on `LivePolicy`) never show credentials: a protocol prints only its class, the scheme, host and non-default port of its base URL, and whether it is authenticated. `Protocol#authenticated?` is true when an `auth:` (or legacy `api_key:`) credential is configured.

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
| `BSVAssociation` | `nil` | Anonymous per-IP limit is not published |
| `TAAL` | `nil` | Depends on subscription tier |

## SDK Entry Points

The SDK exposes three stable entry points for the network layer:

```ruby
# Broadcasting — via a provider (GorillaPool ARC by default)
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

### Timeouts and unknown outcomes

Every request has explicit timeouts (10 s to open the connection, 30 s to read, 30 s to write) and is never retried. A transport failure, such as a timeout or a refused connection, does not raise: it comes back as a failed `ProtocolResponse` with an `error_message`. A read or write timeout on a broadcast means the transaction may already have reached the service, so the outcome is unknown. Resubmit the identical transaction (services treat a repeat submission idempotently) and never rebuild it with different inputs, which could produce a conflicting double spend. ARC's `wait_for:` option holds the response open until the requested status is reached, so it must fit within the 30 s read timeout.

> **Note on `ChainTrackers`:** `ChainTrackers::WhatsOnChain` is a legacy facade that
> wraps WhatsOnChain's chain-info endpoint directly. It continues to work unchanged.
> `ChainTrackers::Chaintracks` (the former Arcade Chaintracks wrapper) has been removed
> and replaced by the provider-routed porcelain described below. If you were using
> `ChainTrackers::Chaintracks` or `ChainTrackers.default`, migrate to
> `ChainTracker.default`.

## Provider-routed Semantic Operations

The Network module distinguishes **wire protocols** (ARC, Arcade, Chaintracks, JungleBus,
WoCREST, Ordinals, TAALBinary) from **semantic capabilities** (verify merkle root, broadcast tx,
fetch fee policy). A wire protocol knows how to speak to one class of service. A
semantic operation — like "what is the current chain height?" — may be satisfiable by
several different wire protocols depending on which provider is in use.

`BSV::Transaction::ChainTracker` is the first example of this pattern. Rather than
binding to a single wire protocol (Chaintracks, WoCREST, or otherwise), it accepts any
`Provider` and routes `:get_block_header` and `:current_height` through that provider's
registered protocols:

```ruby
# Default: GorillaPool provider (JungleBus serves both :current_height
# and :get_block_header). No credentials required.
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
or any other ARC-compatible endpoint.

**Providers are configuration.** A provider is a named bundle of protocol instances
with URLs and credentials. Adding a new provider means creating a new configuration —
no code changes to protocols or facades.

**URLs live in one place.** Provider defaults are the single source of truth for
endpoint URLs. No magic strings in protocols, facades, or application code.

**Porcelain delegates its HTTP.** `ChainTracker` wraps a `Provider` and dispatches `:get_block_header` and `:current_height` through `Provider#call`, so a different provider can be substituted at construction; `ChainTracker.default` uses GorillaPool. `ChainTrackers::WhatsOnChain` is a `ChainTracker` that calls the WhatsOnChain provider's WoCREST protocol. `FeeModels::LivePolicy` fetches its fee policy through `Protocols::ARC`. None of them makes its own HTTP requests, so all inherit the protocol layer's timeouts, transport-error handling and credential-free `inspect`.

## How It Fits Together

```
Application code
    ↓ calls
Porcelain (ChainTracker, ChainTrackers::WhatsOnChain, FeeModels::LivePolicy)
    ↓ delegates to
Protocols (ARC, Arcade, WoCREST, Chaintracks, JungleBus, ...)
    ↓ hosted by
Providers (GorillaPool, WhatsOnChain, TAAL, BSVAssociation)
    ↓ dispatches via
HTTP (Net::HTTP or injectable client)
```

See [Examples](examples.md) for concrete usage patterns.
