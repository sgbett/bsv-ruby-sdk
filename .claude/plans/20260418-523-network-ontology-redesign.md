# Network Ontology Redesign — Protocol Layer (DSL)

## Context

The Phases 1-5 implementation conflated protocols with providers. ARC is a protocol spec,
not a provider — GorillaPool and TAAL both host instances. The current `Providers::ARC` class
hard-codes wire format for one protocol but names itself after that protocol, not the provider.

The full endpoint inventory (`tmp/provider-inventory.md`) reveals 3 providers, 5+ protocols,
and 50 candidate commands (we have 11). The correct ontology is:

**Provider =1:M=> Protocol =1:M=> Command**

### Design principles

- **Commands** are set-in-stone BSV concepts — "broadcast a transaction", "check UTXO spent status"
- **Protocols** are the wire format for groups of commands — defined via Ruby DSL, not YAML
- **Protocol groupings** (ARC, Chaintracks, Tokens) are naming conventions that may shift as the
  ecosystem evolves — they should be easy to add, rename, split, or merge
- **Providers** are pure configuration — a named entity with URLs and credentials
- **SDK Facades** are stable imperative interfaces (`ARC`, `WhatsOnChain`, `ChainTracker`) that
  consumers already use — they stay, but become thin delegates to the Protocol/Registry layer
- **Code structure** should capture immutable BSV concepts; **configuration** should capture
  the flux of providers and their protocol offerings

## Architecture

```
SDK Facades (stable imperative API — consumers use these)
───────────────────────────────────────────────────────────
BSV::Network::ARC            #broadcast(tx) → BroadcastResponse | raise
BSV::Network::WhatsOnChain   #fetch_utxos(addr) → [UTXO], #fetch_transaction(txid) → Transaction
ChainTrackers::WhatsOnChain  #valid_root_for_height?(root, h) → Bool, #current_height → Int
        │
        │  delegate to
        ▼
Commands (immutable BSV concepts — code)
    :broadcast  :get_tx  :is_utxo  :current_height  ... (50)
        │
        │  served by
        ▼
Protocols (wire format DSL — code, but easy to add/change)
    ARC:         endpoint :broadcast, :post, '/v1/tx'
    Chaintracks: endpoint :current_height, :get, '/chaintracks/v2/tip'
    WoC REST:    endpoint :get_tx, :get, '/tx/{txid}/hex'
    (future)     subscription :on_tx, '/woc', event: 'tx'
        │
        │  hosted by
        ▼
Providers (configuration — runtime composition)
    GorillaPool: ARC @ arcade.gorillapool.io, Chaintracks @ same, Ordinals @ ordinals...
    TAAL:        ARC @ arc.taal.com, Binary @ api.taal.com
    WhatsOnChain: WoC REST @ api.whatsonchain.com

Registry (plumbing — code, unchanged)
    register(provider), call(:command, *args), failover
```

## SDK Facades — Preserved, Hollowed Out

Three existing classes are **SDK machinery** that consumers depend on. They stay at
their current names but become thin delegates to the Registry/Protocol layer.

### BSV::Network::ARC — Broadcaster facade

```ruby
class BSV::Network::ARC
  # .default still works, still reads ENV['BSV_ARC_MAINNET_URL']
  def self.default(testnet: false, **opts)
    url = testnet ? BSV::TESTNET_URL : BSV::MAINNET_URL
    new(url, **opts)
  end

  def initialize(url, api_key: nil, **opts)
    # Constructs a single-provider Registry internally:
    # GorillaPool provider with ARC protocol at the given URL
    provider = Provider.new('ARC') { |p| p.protocol Protocols::ARC, base_url: url, api_key: api_key }
    @registry = Registry.new.register(provider)
  end

  # Same contract as always — returns BroadcastResponse, raises BroadcastError
  def broadcast(tx)
    result = @registry.call(:broadcast, tx)
    raise BroadcastError.new(result.message, arc_status: result.metadata[:arc_status]) unless result.success?
    BroadcastResponse.new(txid: result.data[:txid], tx_status: result.data[:status])
  end
end
```

Consumers can still do `ARC.default` for GorillaPool, or `ARC.new('https://arc.taal.com')`
for TAAL — same class, different URL, backed by the same ARC protocol definition.
The protocol is the constant; the provider configuration varies.

### BSV::Network::WhatsOnChain — Chain data facade

```ruby
class BSV::Network::WhatsOnChain
  def initialize(network: :mainnet, http_client: nil)
    provider = Provider.new('WhatsOnChain') { |p|
      p.protocol Protocols::WoCREST, base_url: '...', network: network, http_client: http_client
    }
    @registry = Registry.new.register(provider)
  end

  # Returns UTXO objects (not hashes) — preserves existing contract
  def fetch_utxos(address)
    result = @registry.call(:get_utxos, address)
    result.data.map { |u| UTXO.new(tx_hash: u[:tx_hash], tx_pos: u[:tx_pos], satoshis: u[:satoshis], height: u[:height]) }
  end

  # Returns a parsed Transaction object (not hex) — preserves existing contract
  def fetch_transaction(txid)
    result = @registry.call(:get_tx, txid)
    BSV::Transaction::Transaction.from_hex(result.data)
  end
end
```

### BSV::Transaction::ChainTrackers::WhatsOnChain — SPV facade

```ruby
class BSV::Transaction::ChainTrackers::WhatsOnChain
  def initialize(network: :main, api_key: nil, http_client: nil)
    provider = Provider.new('WhatsOnChain') { |p|
      p.protocol Protocols::WoCREST, base_url: '...', network: network, api_key: api_key, http_client: http_client
    }
    @registry = Registry.new.register(provider)
  end

  def valid_root_for_height?(root, height)
    result = @registry.call(:valid_root, root, height)
    result.success? && result.data == true
  end

  def current_height
    result = @registry.call(:current_height)
    result.success? ? result.data : nil
  end
end
```

### Key insight

The facades are **contract translators**:
- Protocol layer speaks Results (Success/Error/NotFound with hashes)
- `ARC` facade speaks exceptions (BroadcastResponse/BroadcastError)
- `WhatsOnChain` facade speaks domain objects (UTXO, Transaction)
- `ChainTracker` facade speaks primitives (Boolean, Integer)

Each facade constructs its own single-provider Registry internally. But consumers
who want the full multi-provider failover use the Registry directly.

## Protocol DSL

Ruby DSL chosen over YAML because:
- ~30-40% of commands need custom logic (ARC EF format, TAAL binary quirks, is_utxo fallback)
- Response normalisation is inline: `response: ->(body) { JSON.parse(body)['blocks'] }`
- Escape hatches are natural: `def call_broadcast(tx) ... end`
- One file per protocol — everything in one place
- Extensible to WebSocket subscriptions in future
- The DSL lines ARE the configuration — as readable as YAML, with Ruby's power when needed

### Protocol base class

```ruby
class BSV::Network::Protocol
  class << self
    def endpoint(command_name, http_method, path_template, response: :raw)
      # Stores { command_name => { method:, path:, response: } }
    end

    def subscription(event_name, path, **opts)
      # Future: WebSocket subscription definition
    end

    def commands
      # Returns Set of command names this protocol serves
    end
  end

  def initialize(base_url:, api_key: nil, network: nil, http_client: nil)
  end

  def call(command_name, *args, **kwargs)
    # 1. Look up endpoint definition
    # 2. If call_<name> method exists, use it (escape hatch)
    # 3. Otherwise: interpolate path, make HTTP request, apply response handler
    # 4. Wrap in Result::Success / Error / NotFound
  end
end
```

### Concrete protocol examples

```ruby
class BSV::Network::Protocols::ARC < BSV::Network::Protocol
  endpoint :broadcast,      :post, '/v1/tx'
  endpoint :broadcast_many, :post, '/v1/txs'
  endpoint :get_tx_status,  :get,  '/v1/tx/{txid}'
  endpoint :get_policy,     :get,  '/v1/policy'
  endpoint :health,         :get,  '/v1/health'

  def call_broadcast(tx, wait_for: nil, skip_fee_validation: nil, **)
    # EF format, rejection detection, callback headers
  end
end

class BSV::Network::Protocols::Chaintracks < BSV::Network::Protocol
  endpoint :get_block_header, :get, '/chaintracks/v2/header/height/{height}'
  endpoint :current_height,   :get, '/chaintracks/v2/tip', response: ->(body) { JSON.parse(body)['height'] }
end

class BSV::Network::Protocols::WoCREST < BSV::Network::Protocol
  endpoint :get_tx,           :get,  '/tx/{txid}/hex'
  endpoint :get_utxos,        :get,  '/address/{address}/confirmed/unspent', response: :json_array
  endpoint :is_utxo,          :get,  '/tx/{txid}/{vout}/spent'
  endpoint :is_utxo_bulk,     :post, '/utxos/spent'
  endpoint :current_height,   :get,  '/chain/info', response: ->(body) { JSON.parse(body)['blocks'] }
  endpoint :get_block_header, :get,  '/block/{height}/header'
  endpoint :get_merkle_path,  :get,  '/tx/{txid}/proof/tsc'
  endpoint :broadcast,        :post, '/tx/raw'
  endpoint :health,           :get,  '/health'
  # ... all 40+ WoC commands
end
```

### Provider as configuration

```ruby
gorillapool = BSV::Network::Provider.new('GorillaPool') do |p|
  p.protocol Protocols::ARC,         base_url: 'https://arcade.gorillapool.io'
  p.protocol Protocols::Chaintracks, base_url: 'https://arcade.gorillapool.io'
  p.protocol Protocols::Ordinals,    base_url: 'https://ordinals.gorillapool.io'
end

taal = BSV::Network::Provider.new('TAAL') do |p|
  p.protocol Protocols::ARC,        base_url: 'https://arc.taal.com', api_key: ENV['TAAL_KEY']
  p.protocol Protocols::TAALBinary, base_url: 'https://api.taal.com', api_key: ENV['TAAL_KEY']
end

woc = BSV::Network::Provider.new('WhatsOnChain') do |p|
  p.protocol Protocols::WoCREST, base_url: 'https://api.whatsonchain.com/v1/bsv/{network}',
                                  network: :main, api_key: ENV['WOC_KEY']
end

registry = BSV::Network::Registry.new
registry.register(gorillapool)
registry.register(taal, only: [:broadcast])
registry.register(woc)
```

## Phased Implementation

### Phase A — Protocol base class + DSL

New file: `gem/bsv-sdk/lib/bsv/network/protocol.rb`

- `endpoint` class macro: stores command → { method, path_template, response_handler }
- `commands` class method: returns Set of command names
- `call(command, *args, **kwargs)`: dispatch with URL interpolation + HTTP + Result wrapping
- `default_call(command, **path_params)`: make the HTTP call without escape hatch
- Response handlers: `:raw`, `:json`, `:json_array`, custom lambda
- HTTP status → Result mapping: 2xx → Success, 404 → NotFound, 429/5xx → Error(retryable)
- `subscription` class macro: placeholder for future WebSocket support

### Phase B — Concrete protocols

- `Protocols::ARC` (broadcast logic as escape hatch, rest via DSL)
- `Protocols::WoCREST` (40+ endpoints, escape hatches for is_utxo fallback, field remapping)
- `Protocols::Chaintracks` (2 endpoints, pure DSL)
- `Protocols::TAALBinary` (1 endpoint, binary format escape hatch)
- `Protocols::Ordinals` (2 endpoints, pure DSL)

### Phase C — Redefine Provider as configuration

- Provider becomes named container of protocol instances
- Provider.new block DSL for protocol registration
- Registry accepts Providers (same duck type — commands + call)

### Phase D — Hollow out SDK facades

- `BSV::Network::ARC` — keeps name, API, `#broadcast(tx)` contract, `.default`.
  Internally constructs a single-provider Registry with `Protocols::ARC`.
  `ARC.new(url)` → any ARC host. `ARC.default` → GorillaPool via ENV.
- `BSV::Network::WhatsOnChain` — keeps `#fetch_utxos`, `#fetch_transaction`.
  Internally delegates to `Protocols::WoCREST`. Returns UTXO objects and Transaction objects.
- `ChainTrackers::WhatsOnChain` — keeps `#valid_root_for_height?`, `#current_height`.
  Internally delegates to `Protocols::WoCREST`.
- Delete: `RegistryBroadcaster`, `RegistryChainTracker` (subsumed by the hollowed facades)
- Delete: `LegacyChainProviderAdapter`, `LegacyBroadcasterAdapter` (no legacy path)
- Delete: `ChainProvider`, `NullChainProvider`, `WhatsOnChainProvider`, deprecation code

### Phase E — Expand command vocabulary

Add commands incrementally, priority order:
1. `:is_utxo_bulk`, `:get_tx_status_bulk` — janitor performance
2. `:get_block_header`, `:health` — SPV and failover
3. `:get_balance`, `:is_address_used` — wallet operations
4. Token commands — future overlay layer
5. WebSocket subscriptions — future real-time

## Files

### New
- `gem/bsv-sdk/lib/bsv/network/protocol.rb` — Protocol base class with DSL
- `gem/bsv-sdk/lib/bsv/network/protocols/arc.rb`
- `gem/bsv-sdk/lib/bsv/network/protocols/woc_rest.rb`
- `gem/bsv-sdk/lib/bsv/network/protocols/chaintracks.rb`
- `gem/bsv-sdk/lib/bsv/network/protocols/ordinals.rb`
- `gem/bsv-sdk/lib/bsv/network/protocols/taal_binary.rb`
- Specs for all above

### Refactor (hollow out)
- `gem/bsv-sdk/lib/bsv/network/arc.rb` — thin delegate to Protocols::ARC via Registry
- `gem/bsv-sdk/lib/bsv/network/whats_on_chain.rb` — thin delegate to Protocols::WoCREST
- `gem/bsv-sdk/lib/bsv/transaction/chain_trackers/whats_on_chain.rb` — thin delegate
- `gem/bsv-sdk/lib/bsv/network/provider.rb` — becomes configuration container

### Delete
- `gem/bsv-sdk/lib/bsv/network/providers/arc.rb` — replaced by Protocols::ARC
- `gem/bsv-sdk/lib/bsv/network/providers/whats_on_chain.rb` — replaced by Protocols::WoCREST
- `gem/bsv-wallet/lib/bsv/wallet_interface/chain_provider.rb`
- `gem/bsv-wallet/lib/bsv/wallet_interface/null_chain_provider.rb`
- `gem/bsv-wallet/lib/bsv/wallet_interface/whats_on_chain_provider.rb`
- `gem/bsv-wallet/lib/bsv/wallet_interface/adapters/legacy_*.rb`
- `gem/bsv-wallet/lib/bsv/wallet_interface/adapters/registry_broadcaster.rb` (subsumed)
- `gem/bsv-wallet/lib/bsv/wallet_interface/adapters/registry_chain_tracker.rb` (subsumed)
- Deprecation warnings, BSV_SUPPRESS_DEPRECATIONS

### Modify
- `gem/bsv-sdk/lib/bsv/network/registry.rb` — accept new Provider shape
- `gem/bsv-sdk/lib/bsv/network/commands.rb` — expand toward 50 commands
- `gem/bsv-wallet/lib/bsv/wallet_interface/wallet_client.rb` — simplified constructor
- `gem/bsv-sdk/lib/bsv/mcp/tools/*.rb` — MCP tools already use ARC/WhatsOnChain facades, no change needed

## Verification

1. `bundle exec rake` — all specs pass
2. `bundle exec rubocop` — clean
3. `BSV::Network::ARC.default.broadcast(tx)` still works (facade preserved)
4. `BSV::Network::WhatsOnChain.new.fetch_utxos(addr)` still returns UTXO objects
5. `BSV::Network::ARC.new('https://arc.taal.com').broadcast(tx)` works (different provider, same facade)
6. `bundle exec rake network:commands` — shows expanded command list
7. `bundle exec rake network:capabilities` — shows Provider × Protocol × Command matrix
8. Adding a new protocol = one .rb file with endpoint declarations
9. Adding a new provider = configuration (Provider.new block)
10. MCP tools unchanged — they use the facades

## Notes

- Facades are **contract translators**: Protocol speaks Results, facades speak
  exceptions/domain objects/primitives as their consumers expect
- Each facade internally constructs a single-provider Registry — simple, testable
- Consumers who want multi-provider failover use the Registry directly
- The Protocol DSL builds introspectable data structures — capability_matrix
  and documentation generation work automatically
- WebSocket support is a future extension point — `subscription` macro defined but not implemented
- `ARC.new(url)` means "give me the ARC protocol at this URL" — the consumer
  doesn't need to know or care which company hosts it
