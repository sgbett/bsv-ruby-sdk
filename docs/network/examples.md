---
title: Examples
nav_order: 2
parent: Network
---

# Network Examples

## Quick Start — Using Defaults

The simplest path uses `.default` on provider and tracker classes. No configuration needed.

### Broadcast a transaction

```ruby
# GorillaPool ARC (public endpoint, no auth required)
provider = BSV::Network::Providers::GorillaPool.default
result = provider.call(:broadcast, tx)
puts result.data['txid'] if result.http_success?
```

A broadcast that times out leaves the outcome unknown: the transaction may already have reached the service. Resubmit the identical transaction (safe, services treat it idempotently) and never rebuild it with different inputs.

### Fetch UTXOs for an address

```ruby
woc = BSV::Network::Providers::WhatsOnChain.default
result = woc.call(:get_utxos, '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa')
if result.http_success?
  result.data.each { |u| puts "#{u['tx_hash']}:#{u['tx_pos']} — #{u['value']} sats" }
end
```

### Verify a merkle root (SPV)

```ruby
tracker = BSV::Transaction::ChainTrackers::WhatsOnChain.default
valid = tracker.valid_root_for_height?('145b78dc...', 850_000)
puts valid ? 'confirmed' : 'not found'
```

### Use testnet

Every `.default` accepts `testnet: true`:

```ruby
provider = BSV::Network::Providers::GorillaPool.default(testnet: true)
woc = BSV::Network::Providers::WhatsOnChain.default(testnet: true)
tracker = BSV::Transaction::ChainTrackers::WhatsOnChain.default(testnet: true)
```

## Working with Providers Directly

For more control, use the provider defaults directly. A provider composes one or more
protocols and exposes all their commands through a single `call` interface.

### GorillaPool provider

```ruby
gp = BSV::Network::Providers::GorillaPool.default

# Broadcasting (via the ARC protocol)
result = gp.call(:broadcast, tx)
puts result.data['txStatus'] if result.http_success?  # => "SEEN_ON_NETWORK"

# See what commands are available
puts gp.commands.to_a.sort
# => [:broadcast, :broadcast_many, :current_height, :get_address_meta, ...,
#     :get_tx_status, :get_utxos, :health]
```

### BSV Broadcaster (opt-in)

`Providers::BSVAssociation` points at the BSV Association's BSV Broadcaster (formerly Arcade). Nothing in the SDK defaults to it. It needs no key; anonymous use is rate-limited per IP address.

```ruby
bsv = BSV::Network::Providers::BSVAssociation.default   # or .default(testnet: true)

# Extended Format only: a transaction whose inputs lack source outputs, or a
# string that is not Extended Format, raises ArgumentError and sends nothing.
result = bsv.call(:broadcast, tx)
puts result.data['txStatus'] if result.http_success?   # => "RECEIVED"
puts result.data['status']                              # => 202 (the HTTP code, not a string)

# Status tracking is per instance: only transactions submitted to this
# instance are known to it.
result = bsv.call(:get_tx_status, result.data['txid'])
puts result.data['txStatus']

# Fee policy
puts bsv.call(:get_policy).data
```

On 429 or 503 the response is a failed `ProtocolResponse` with `retryable?` true.

### WhatsOnChain provider

```ruby
woc = BSV::Network::Providers::WhatsOnChain.default

result = woc.call(:get_tx, 'abc123...')
puts result.data if result.http_success?  # raw hex

result = woc.call(:is_utxo, 'abc123...', 0)
puts result.data  # true (unspent) or false (spent)

result = woc.call(:get_exchange_rate)
puts result.data  # { "rate" => 42.50, ... }
```

### Introspection

```ruby
gp = BSV::Network::Providers::GorillaPool.default

# Which protocol handles a specific command?
proto = gp.protocol_for(:broadcast)
puts proto.class  # => BSV::Network::Protocols::ARC

# Capability matrix — what each protocol serves
gp.capability_matrix.each do |proto, commands|
  puts "#{proto.class.name.split('::').last}: #{commands.join(', ')}"
end
# ARC: broadcast, broadcast_many, get_policy, get_tx_status, health
# Ordinals: get_balance, get_chain_tip, get_merkle_path, get_spend, get_tx, get_tx_details, get_utxos
# JungleBus: current_height, get_address_meta, get_address_txs, get_block_header, get_block_headers
```

## Custom Providers

### Point ARC at a different host

```ruby
# Use TAAL's ARC instance (it requires a key)
arc = BSV::Network::Protocols::ARC.new(
  base_url: 'https://arc.taal.com',
  api_key: 'my-taal-key'
)
result = arc.call(:broadcast, tx)
puts result.data['txid'] if result.http_success?
```

### Build a provider from scratch

```ruby
my_provider = BSV::Network::Provider.new('MyInfra') do |p|
  # Use TAAL for broadcasting
  p.protocol BSV::Network::Protocols::ARC,
    base_url: 'https://arc.taal.com',
    api_key: ENV['TAAL_KEY']

  # Use WhatsOnChain for chain data
  p.protocol BSV::Network::Protocols::WoCREST,
    base_url: 'https://api.whatsonchain.com/v1/bsv/main',
    api_key: ENV['WOC_KEY']
end

# Now broadcasts go to TAAL, chain queries go to WoC
result = my_provider.call(:broadcast, tx)     # → TAAL ARC
result = my_provider.call(:get_tx, txid)      # → WoC
result = my_provider.call(:is_utxo, txid, 0)  # → WoC
```

### Mix providers for failover

```ruby
# Primary: GorillaPool ARC for broadcasting
# Fallback: BSV Broadcaster (Arcade). Both return ARC-shaped bodies (txid, txStatus).
# The fallback needs Extended Format, so the transaction's inputs must carry
# their source outputs.
primary = BSV::Network::Providers::GorillaPool.default
fallback = BSV::Network::Providers::BSVAssociation.default

result = primary.call(:broadcast, tx)
if !result.http_success? && result.retryable?
  result = fallback.call(:broadcast, tx)  # same transaction, different service
end
```

### Private ARC instance

```ruby
# Your own ARC node
my_arc = BSV::Network::Provider.new('PrivateARC') do |p|
  p.protocol BSV::Network::Protocols::ARC,
    base_url: 'https://arc.mycompany.internal',
    api_key: ENV['ARC_INTERNAL_KEY']
end

result = my_arc.call(:broadcast, tx)
```

## Working with Protocols Directly

Protocols are the wire format layer. You rarely need to use them directly, but they're
useful for testing or when building custom infrastructure.

### Instantiate a protocol

```ruby
# TAAL ARC
arc = BSV::Network::Protocols::ARC.new(
  base_url: 'https://arc.taal.com',
  api_key: 'my-taal-key'
)

result = arc.call(:broadcast, tx)
# result is a ProtocolResponse; result.data['txStatus'] => "SEEN_ON_NETWORK"

# BSV Broadcaster (Arcade) — a distinct protocol: Extended Format only, root paths
arcade = BSV::Network::Protocols::Arcade.new(
  base_url: 'https://arcade-v2-us-1.bsvblockchain.tech'
)

result = arcade.call(:broadcast, tx)
# result.data['txStatus'] => "RECEIVED"; result.data['status'] => 202
```

### Result types

All protocol calls return a `BSV::Network::ProtocolResponse`:

```ruby
result = woc_protocol.call(:get_tx, txid)

if result.http_success?
  puts result.data           # the response payload
elsif result.http_not_found?
  puts 'transaction not found'
else
  puts result.error_message  # error description
  puts result.retryable?     # can we try another provider?
end
```

### Define a custom protocol

For a service with a non-standard API (e.g. a Cloudflare Worker):

```ruby
class MyChaintracks < BSV::Network::Protocol
  endpoint :current_height,   :get, '/currentHeight',
    response: ->(body) { JSON.parse(body)['value'] }

  endpoint :get_block_header, :get, '/findHeaderHexForHeight',
    response: ->(body) { JSON.parse(body)['value'] }

  endpoint :is_valid_root,    :get, '/isValidRootForHeight',
    response: ->(body) { JSON.parse(body)['value'] }
end

# Use it in a provider
my_tracker = BSV::Network::Provider.new('MyTracker') do |p|
  p.protocol MyChaintracks,
    base_url: 'https://my-chaintracks.workers.dev'
end

result = my_tracker.call(:current_height)
puts result.data  # => 945398
```

## Auth Configuration

The SDK supports three authentication mechanisms via the `auth:` hash. The SDK does not
read environment variables for credentials — that is a consumer concern. Pass credentials
in at construction time.

### Bearer token

Use `auth: { bearer: 'token' }` for services that expect `Authorization: Bearer <token>`.
This is the standard form for TAAL ARC, GorillaPool and the BSV Broadcaster.

```ruby
# GorillaPool with a bearer token — sent to every GorillaPool host the
# provider composes (ARC, Ordinals and JungleBus)
gp = BSV::Network::Providers::GorillaPool.default(auth: { bearer: ENV['GP_TOKEN'] })

# TAAL with a bearer token — required: TAAL's ARC answers 401 without one,
# except on /v1/policy
taal = BSV::Network::Providers::TAAL.default(auth: { bearer: ENV['TAAL_TOKEN'] })
```

### Raw API key (no Bearer prefix)

Use `auth: { api_key: 'key' }` for services that expect a bare key in the
`Authorization` header. This is the WhatsOnChain style.

```ruby
woc = BSV::Network::Providers::WhatsOnChain.default(auth: { api_key: ENV['WOC_KEY'] })
```

### Custom header

Use `auth: { api_key: 'key', header: 'X-Header-Name' }` when the service expects
credentials in a non-standard header.

```ruby
my_provider = BSV::Network::Providers::GorillaPool.default(
  auth: { api_key: ENV['MY_KEY'], header: 'Api-Key' }
)
```

### Auth mechanisms summary

| `auth:` form | Header sent |
|---|---|
| `{ bearer: 'token' }` | `Authorization: Bearer token` |
| `{ api_key: 'key' }` | `Authorization: key` (no prefix) |
| `{ api_key: 'key', header: 'X-Custom' }` | `X-Custom: key` |
| `:none` / omitted | No auth header |

### Checking auth status

Providers expose `authenticated?` and `auth` accessors for introspection:

```ruby
provider = BSV::Network::Providers::WhatsOnChain.mainnet(auth: { api_key: 'my-key' })
provider.authenticated?   # => true
provider.auth             # => { api_key: 'my-key' }

public_provider = BSV::Network::Providers::GorillaPool.default
public_provider.authenticated?  # => false
public_provider.auth            # => :none
```

### Migration from `api_key:`

The legacy `api_key:` keyword argument is still supported for backwards compatibility.
The new `auth:` hash is the preferred form. Both work; `auth:` takes precedence when
both are supplied.

```ruby
# Legacy — still works on providers
provider = BSV::Network::Providers::GorillaPool.default(api_key: 'my-key')

# Preferred — explicit about the mechanism
provider = BSV::Network::Providers::GorillaPool.default(auth: { bearer: 'my-key' })
```

For WhatsOnChain, the protocol sends a bare key (no `Bearer` prefix). Both the
new `auth: { api_key: 'key' }` form and the legacy `api_key:` shorthand work
correctly — the factory translates the legacy form automatically.

## Rate Limit Metadata

Providers carry a `rate_limit` attribute that declares the requests-per-second limit
appropriate for the configured credentials. **The SDK does not enforce this limit** —
it is metadata for the consumer to use in their own rate-limiting logic (e.g. a token
bucket in an application layer).

```ruby
# Default rate limit for unauthenticated use
woc = BSV::Network::Providers::WhatsOnChain.default
woc.rate_limit   # => 3

# Override for an authenticated tier with higher limits
woc = BSV::Network::Providers::WhatsOnChain.mainnet(
  auth: { api_key: ENV['WOC_KEY'] },
  rate_limit: 25
)
woc.rate_limit   # => 25

# TAAL: nil because it depends on subscription tier
taal = BSV::Network::Providers::TAAL.default
taal.rate_limit  # => nil
```

Default rate limits per provider (unauthenticated tier):

| Provider | `DEFAULT_RATE_LIMIT` |
|----------|---------------------|
| `WhatsOnChain` | 3 req/s |
| `GorillaPool` | 3 req/s |
| `BSVAssociation` | `nil` (anonymous per-IP limit is not published) |
| `TAAL` | `nil` (depends on subscription) |
