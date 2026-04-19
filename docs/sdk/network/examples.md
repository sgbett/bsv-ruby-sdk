# Network Examples

## Quick Start — Using Defaults

The simplest path uses `.default` on the facade classes. No configuration needed.

### Broadcast a transaction

```ruby
arc = BSV::Network::ARC.default
response = arc.broadcast(tx)
puts response.txid
```

### Fetch UTXOs for an address

```ruby
woc = BSV::Network::WhatsOnChain.default
utxos = woc.fetch_utxos('1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa')
utxos.each { |u| puts "#{u.tx_hash}:#{u.tx_pos} — #{u.satoshis} sats" }
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
arc = BSV::Network::ARC.default(testnet: true)
woc = BSV::Network::WhatsOnChain.default(testnet: true)
tracker = BSV::Transaction::ChainTrackers::WhatsOnChain.default(testnet: true)
```

## Working with Providers Directly

For more control, use the provider defaults directly. A provider composes one or more
protocols and exposes all their commands through a single `call` interface.

### GorillaPool provider

```ruby
gp = BSV::Network::Providers::GorillaPool.default

# Broadcasting (via ARC protocol)
result = gp.call(:broadcast, tx)
puts result.data[:txid] if result.success?

# Chain height (via Chaintracks protocol)
result = gp.call(:current_height)
puts result.data if result.success?

# See what commands are available
puts gp.commands.to_a.sort
# => [:broadcast, :broadcast_many, :current_height, :get_block_header,
#     :get_merkle_path, :get_policy, :get_tx, :get_tx_status, :health]
```

### WhatsOnChain provider

```ruby
woc = BSV::Network::Providers::WhatsOnChain.default

result = woc.call(:get_tx, 'abc123...')
puts result.data if result.success?  # raw hex

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
# Chaintracks: current_height, get_block_header
# Ordinals: get_merkle_path, get_tx
```

## Custom Providers

### Point ARC at a different host

```ruby
# Use TAAL's ARC instance instead of GorillaPool
arc = BSV::Network::ARC.new('https://arc.taal.com', api_key: 'my-taal-key')
response = arc.broadcast(tx)
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
# Primary: GorillaPool for everything
# Fallback: TAAL for broadcasting only
primary = BSV::Network::Providers::GorillaPool.default
fallback = BSV::Network::Providers::TAAL.default

result = primary.call(:broadcast, tx)
if result.error? && result.retryable?
  result = fallback.call(:broadcast, tx)  # try TAAL
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
arc = BSV::Network::Protocols::ARC.new(
  base_url: 'https://arcade.gorillapool.io',
  api_key: 'my-key'
)

result = arc.call(:broadcast, tx)
# result is a Result::Success, Result::Error, or Result::NotFound
```

### Result types

All protocol calls return Result objects:

```ruby
result = woc_protocol.call(:get_tx, txid)

case
when result.success?
  puts result.data         # the response payload
when result.not_found?
  puts 'transaction not found'
when result.error?
  puts result.message      # error description
  puts result.retryable?   # can we try another provider?
  puts result.metadata     # structured data (e.g. arc_status)
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

## API Key Configuration

API keys are passed through `**opts` on `.default` or directly on constructors:

```ruby
# Via .default
arc = BSV::Network::ARC.default(api_key: 'my-key')
woc = BSV::Network::WhatsOnChain.default(api_key: 'my-woc-key')

# Via provider
gp = BSV::Network::Providers::GorillaPool.default(api_key: 'my-key')

# Via constructor
arc = BSV::Network::ARC.new('https://arc.taal.com', api_key: 'taal-key')
```

The SDK does not read environment variables for API keys — that's a consumer concern.
Set them however makes sense for your application (ENV vars, Rails credentials,
config files, etc.) and pass them in at construction time.
