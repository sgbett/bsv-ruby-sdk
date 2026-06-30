---
title: Network
nav_order: 4
parent: SDK
---

# Network

The `BSV::Network` module handles broadcasting transactions and querying the blockchain.
The `BSV::Transaction::ChainTracker` class provides SPV verification against block headers.

For the underlying architecture (Protocols, Providers, Commands), see the
[Network Architecture Overview](../network/overview.md) and [Examples](../network/examples.md).

## Broadcasting Transactions

Broadcasting uses the `BSV::Network::Providers` layer. A provider composes one or more
wire protocols and routes commands through a single `call` interface, returning a
`BSV::Network::ProtocolResponse`.

### Default Broadcaster — GorillaPool (Arcade)

The simplest path uses `GorillaPool.default`, which points at GorillaPool's public
Arcade endpoint:

```ruby
provider = BSV::Network::Providers::GorillaPool.default
result = provider.call(:broadcast, tx)

if result.http_success?
  puts result.data['txid']    #=> "abc123..."
else
  puts result.error_message   #=> rejection detail
end
```

For testnet:

```ruby
provider = BSV::Network::Providers::GorillaPool.default(testnet: true)
```

### TAAL ARC

To broadcast via TAAL's ARC endpoint instead:

```ruby
provider = BSV::Network::Providers::TAAL.default(auth: { bearer: ENV['TAAL_KEY'] })
result = provider.call(:broadcast, tx)

if result.http_success?
  puts result.data['txid']      #=> display-order hex (ARC API boundary)
  puts result.data['txStatus']  #=> "SEEN_ON_NETWORK"
end
```

### Custom ARC Endpoint

Point the ARC protocol directly at any ARC-compatible endpoint:

```ruby
arc = BSV::Network::Protocols::ARC.new(
  base_url: 'https://my-arc-server.example.com',
  auth: { bearer: 'my-api-key' }
)
result = arc.call(:broadcast, tx)
```

### ARC Broadcast Options

`call(:broadcast, tx, ...)` forwards keyword options to the ARC escape hatch:

```ruby
result = arc.call(:broadcast, tx,
  wait_for: 'SEEN_ON_NETWORK',   # hold connection until status reached
  skip_fee_validation: true,       # bypass minimum-fee check
  skip_script_validation: true     # bypass script correctness check
)
```

| Option | Description |
|--------|-------------|
| `wait_for` | ARC wait condition: `RECEIVED`, `STORED`, `ANNOUNCED_TO_NETWORK`, `SEEN_ON_NETWORK`, or `MINED` |
| `skip_fee_validation` | Bypass fee check (useful for zero-fee data transactions) |
| `skip_script_validation` | Bypass script validation (useful during testing) |

### Batch Broadcasting

Submit multiple transactions in a single ARC request:

```ruby
# Use the ARC protocol directly for batch support
arc = BSV::Network::Protocols::ARC.new(
  base_url: 'https://arc.taal.com',
  auth: { bearer: ENV['TAAL_KEY'] }
)
result = arc.call(:broadcast_many, [tx1, tx2, tx3])

if result.http_success?
  result.data.each do |entry|
    puts "#{entry['txid']}: #{entry['txStatus']}"
  end
else
  puts result.error_message
end
```

`broadcast_many` returns a `ProtocolResponse`. On success, `result.data` is an array
of per-transaction hashes — each has `txid` and `txStatus`. HTTP-level failures set
`http_success?` to false for the entire batch; per-transaction rejections are
detectable by checking `txStatus` within the array.

### Transaction Status

Query the status of a previously broadcast transaction via ARC:

```ruby
arc = BSV::Network::Protocols::ARC.new(
  base_url: 'https://arc.taal.com',
  auth: { bearer: ENV['TAAL_KEY'] }
)
result = arc.call(:get_tx_status, 'abc123...')  # display-order hex at ARC boundary
if result.http_success?
  puts result.data['txStatus']    #=> "MINED"
  puts result.data['blockHeight'] #=> 800123
end
```

### Callbacks

Pass callback options when building the ARC protocol:

```ruby
arc = BSV::Network::Protocols::ARC.new(
  base_url: 'https://arc.taal.com',
  auth: { bearer: ENV['TAAL_KEY'] },
  callback_url: 'https://my-server.com/tx-status',
  callback_token: 'my-secret-token'
)
```

## SPV Verification

### Chain Trackers

A chain tracker verifies that a merkle root corresponds to a valid block at a specific height. This is essential for BEEF (BRC-62) SPV verification.

```ruby
# Default tracker routes through GorillaPool's JungleBus protocol,
# which serves both :current_height and :get_block_header.
tracker = BSV::Transaction::ChainTracker.default

# Verify a merkle root
tracker.valid_root_for_height?('4a5e1e4b...', 0)  #=> true

# Get current chain tip
tracker.current_height  #=> 800_123
```

For testnet:

```ruby
tracker = BSV::Transaction::ChainTracker.default(testnet: true)
```

### Available Trackers

| Tracker | Endpoint | Usage |
|---------|----------|-------|
| `ChainTracker` | Any Provider exposing `:get_block_header` and `:current_height` | `ChainTracker.default` (uses GorillaPool + JungleBus) |
| `ChainTrackers::WhatsOnChain` | WhatsOnChain API | `ChainTrackers::WhatsOnChain.new(network: :main)` |

### BEEF Verification

Combine a chain tracker with `Beef#verify` for full SPV verification:

```ruby
tracker = BSV::Transaction::ChainTracker.default

beef = BSV::Transaction::Beef.from_binary(beef_bytes)

# Structural validation only
beef.valid?  #=> true

# Full SPV verification against the blockchain
beef.verify(tracker)  #=> true
```

`verify` calls `valid?` for structural checks, then verifies each BUMP's merkle root against the chain tracker.

### Custom Chain Tracker

Implement your own by subclassing `ChainTracker`:

```ruby
class MyTracker < BSV::Transaction::ChainTracker
  def valid_root_for_height?(root, height)
    # Query your block header source
    # Return true if root matches the block at height
  end

  def current_height
    # Return the chain tip height
  end
end
```

## SDK vs Wallet

The SDK (`bsv-sdk`) is **declarative** — it defines data structures, serialisation, and cryptographic operations. The wallet gems (`bsv-wallet`, `bsv-attest`) are **imperative** — they orchestrate workflows.

| Need | Where |
|------|-------|
| Build and sign a transaction | `bsv-sdk` — `BSV::Transaction` |
| Broadcast a transaction | `bsv-sdk` — `BSV::Network::Providers` / `BSV::Network::Protocols::ARC` |
| Verify a BEEF proof | `bsv-sdk` — `BSV::Transaction::Beef#verify` |
| Manage UTXOs and baskets | `bsv-wallet` — `BSV::Wallet::Client` |
| Track output baskets | `bsv-wallet` — basket parameter on outputs |
| Auto-fund transactions | `bsv-wallet` — `create_action` with `auto_fund: true` |
| Attest documents on-chain | `bsv-attest` — `BSV::Attest` |

## MCP Server

The SDK ships with a built-in MCP (Model Context Protocol) server that exposes core BSV operations as tools for AI assistants like Claude Code.

### Setup

Add to your Claude Code MCP configuration (`.mcp.json`):

```json
{
  "mcpServers": {
    "bsv-sdk": {
      "command": "bundle",
      "args": ["exec", "bsv-mcp"],
      "cwd": "/path/to/your/project"
    }
  }
}
```

### Available Tools

| Tool | Description |
|------|-------------|
| `generate_key` | Generate a new random BSV keypair |
| `decode_tx` | Parse and inspect a raw transaction hex |
| `fetch_utxos` | Fetch UTXOs for an address from WhatsOnChain |
| `fetch_tx` | Fetch a transaction by txid from WhatsOnChain |
| `check_balance` | Check the balance of an address or WIF |
| `broadcast_p2pkh` | Build, sign, and broadcast a P2PKH payment |

### Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `BSV_NETWORK` | `main` | Network: `main` or `test` |
| `BSV_ARC_URL` | GorillaPool | Custom ARC endpoint URL |
| `BSV_ARC_API_KEY` | *(none)* | ARC API key — passed as `auth: { bearer: value }` |

See the **[MCP Server Guide](../general/mcp.md)** for full setup instructions, testnet configuration, and example workflows.

## What's Next

- **[Network Architecture](../network/overview.md)** — how Protocols, Providers, and Commands fit together
- **[Network Examples](../network/examples.md)** — custom providers, failover, protocol DSL
- **[Transaction Guide](transaction.md)** — building, signing, fee estimation, BEEF
- **[Getting Started](../guides/getting-started.md)** — key generation, basic transaction construction
- **[MCP Server Guide](../general/mcp.md)** — using BSV tools from AI assistants
