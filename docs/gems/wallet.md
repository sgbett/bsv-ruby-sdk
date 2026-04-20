# Wallet

The `bsv-wallet` gem implements the
[BRC-100](https://bsv.brc.dev/wallet/0100) standard wallet-to-application
interface. It provides `BSV::Wallet::Client` — a local wallet that manages UTXOs,
builds and signs transactions, broadcasts via ARC, and tracks certificates.

## Installation

```ruby
# Gemfile
gem 'bsv-wallet'
```

## Creating a wallet

```ruby
require 'bsv-wallet'

key = BSV::Primitives::PrivateKey.from_wif(ENV['SERVER_WIF'])

wallet = BSV::Wallet::Client.new(
  key,
  broadcaster: BSV::Network::ARC.default
)
```

### Constructor parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `key` | (required) | Private key, WIF string, or `KeyDeriver` |
| `storage` | `FileStore.new` | Persistence adapter (`MemoryStore` for tests, `PostgresStore` for production) |
| `network` | `'mainnet'` | `'mainnet'` or `'testnet'` |
| `broadcaster` | `nil` | Any object responding to `#broadcast(tx)` — use `ARC.default` for GorillaPool ARCADE |
| `broadcast_queue` | `InlineQueue` | Broadcast strategy — `InlineQueue` (synchronous) or `SolidQueueAdapter` (async, PostgreSQL-backed) |
| `chain_provider` | `NullChainProvider` | Blockchain data provider (e.g. `WhatsOnChainProvider`) |
| `fee_estimator` | auto | Custom fee estimator (defaults to `SatoshisPerKilobyte`) |
| `coin_selector` | auto | Custom coin selection strategy |
| `change_generator` | auto | Custom change output generation |

## Core operations

### create_action

Builds, signs, and optionally broadcasts a transaction:

```ruby
result = wallet.create_action({
  description: 'Pay invoice',
  outputs: [{
    locking_script: '76a914...88ac',
    satoshis: 1000,
    output_description: 'Payment',
    basket: 'payments',
    tags: ['invoice-42']
  }]
})

result[:txid]     # => "abc123..."
result[:tx]       # => [BEEF bytes as integers]
```

When a `broadcaster` is configured, `create_action` handles the full
lifecycle: UTXO selection, transaction construction, signing, ARC broadcast,
and state promotion. On broadcast failure, locked UTXOs are rolled back
automatically.

#### Auto-funding

If no `inputs` are specified, the wallet selects spendable UTXOs
automatically (coin selection), adds change outputs, and manages the
`pending` → `spent`/`spendable` state transitions.

#### Options

```ruby
wallet.create_action({
  description: 'Payment',
  outputs: [...],
  options: {
    accept_delayed_broadcast: true,  # defer broadcast to background queue
    no_send: true                    # build tx but don't broadcast
  }
})
```

### sign_action

Signs a previously created action (two-phase commit):

```ruby
result = wallet.sign_action({
  reference: pending_reference,
  spends: { '0' => { unlocking_script: '...' } }
})
```

### abort_action

Cancels a pending action and releases locked UTXOs:

```ruby
wallet.abort_action({ reference: pending_reference })
```

### list_actions

Query stored actions with filtering and pagination:

```ruby
actions = wallet.list_actions({
  labels: ['payments'],
  label_query_mode: 'any',
  include_labels: true,
  limit: 10,
  offset: 0
})
```

### list_outputs

Query tracked outputs:

```ruby
outputs = wallet.list_outputs({
  basket: 'payments',
  tags: ['invoice-42'],
  include_spent: false,
  limit: 50,
  offset: 0
})
```

### internalize_action

Accept an incoming payment by internalising a BEEF transaction:

```ruby
wallet.internalize_action({
  tx: beef_bytes,           # Atomic BEEF binary
  outputs: [{
    output_index: 0,
    protocol: 'wallet payment',
    payee: { derivation_prefix: '...', derivation_suffix: '...' }
  }],
  description: 'Received payment'
})
```

The full internalize → create → broadcast round-trip is exercised by the integration
spec suite. `internalize_action` persists every transaction in the BEEF (not just the
subject), so ancestor chain data is available when the wallet later builds a new
transaction spending the internalised UTXO. This ensures `to_ef_hex` can serialise the
spending transaction correctly for ARC broadcast, even when the parent is unconfirmed.

## Status meanings

Each action stored by the wallet carries a `status` field that reflects its
current lifecycle state:

| Status | Meaning |
|--------|---------|
| `'nosend'` | Transaction built but not broadcast (caller opted into `options: { no_send: true }`) |
| `'sending'` | Broadcast queued for background processing (async adapter); worker has not yet attempted broadcast |
| `'unproven'` | Broadcast succeeded; awaiting merkle proof |
| `'completed'` | Merkle proof received and stored |
| `'failed'` | Broadcast attempted and rejected by the network |

> **Note for consumers:** Querying `list_actions(status: 'completed')` returns
> fewer results under the current taxonomy until a proof-watcher is implemented
> (out of scope for the current release). Most fresh broadcasts will be in
> `'unproven'` state until their merkle proof arrives. This aligns with the TS
> reference SDK's semantics. To find all successfully-broadcast actions, query
> for both `'unproven'` and `'completed'`, or rely on `'failed'` to detect
> broadcast rejection.

This taxonomy matches the [wallet-toolbox](https://github.com/bitcoin-sv/wallet-toolbox)
reference implementation (BRC-100).

## Balance and UTXOs

```ruby
wallet.balance                          # total sats across all baskets
wallet.balance(basket: 'payments')      # sats in a specific basket
wallet.spendable_balance                # only immediately spendable sats
```

## Certificates

BRC-100 certificate operations for identity and credential management:

```ruby
# Acquire a certificate
wallet.acquire_certificate({
  type: 'identity',
  certifier: '02abc...',
  acquisitionProtocol: 'direct',
  fields: { name: 'Alice' }
})

# List certificates
wallet.list_certificates({
  certifiers: ['02abc...'],
  types: ['identity']
})

# Prove selective disclosure
wallet.prove_certificate({
  certificate: cert,
  fields_to_reveal: ['name'],
  verifier: '02def...'
})
```

## Storage adapters

The wallet persists UTXOs, actions, certificates, and proofs via a
pluggable `StorageAdapter`:

| Adapter | Gem | Persistence | Thread-safe | Use case |
|---------|-----|-------------|-------------|----------|
| `MemoryStore` | bsv-wallet | None | Yes | Tests |
| `FileStore` | bsv-wallet | JSON files | No | Development |
| `PostgresStore` | bsv-wallet-postgres | PostgreSQL | Yes | Production |

```ruby
# Production setup with PostgreSQL
require 'bsv-wallet-postgres'

db = Sequel.connect(ENV['DATABASE_URL'])
BSV::Wallet::PostgresStore.migrate!(db)
store = BSV::Wallet::PostgresStore.new(db)

wallet = BSV::Wallet::Client.new(
  key,
  storage: store,
  broadcaster: BSV::Network::ARC.default
)
```

See the [Wallet Postgres guide](wallet-postgres.md) for production
deployment details.

## Broadcast queue

The `BroadcastQueue` interface controls how transactions are dispatched
after construction:

| Adapter | Gem | Async | Description |
|---------|-----|-------|-------------|
| `InlineQueue` | bsv-wallet | No | Default — broadcasts synchronously in `create_action` |
| `SolidQueueAdapter` | bsv-wallet-postgres | Yes | Background worker with PostgreSQL job table |

```ruby
# Async broadcast with SolidQueueAdapter
adapter = BSV::Wallet::SolidQueueAdapter.new(
  db: db,
  storage: store,
  broadcaster: BSV::Network::ARC.default
)
adapter.start

wallet = BSV::Wallet::Client.new(
  key,
  storage: store,
  broadcast_queue: adapter
)

# On shutdown:
adapter.drain
```

See the [Wallet Postgres guide](wallet-postgres.md#async-broadcast-queue)
for details.

## Error handling

| Error class | When |
|-------------|------|
| `InsufficientFundsError` | Not enough spendable UTXOs for the requested amount |
| `WalletError` | General wallet operation failure |
| `InvalidParameterError` | Invalid arguments to a wallet method |
| `UnsupportedActionError` | Requested operation not supported |
