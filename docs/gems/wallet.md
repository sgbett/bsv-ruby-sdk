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

## Quick start

```ruby
require 'bsv-wallet'

key = BSV::Primitives::PrivateKey.from_wif(ENV['SERVER_WIF'])

wallet = BSV::Wallet::Client.new(
  key,
  broadcaster: BSV::Network::ARC.default
)

# Create a transaction
result = wallet.create_action(
  description: 'Pay invoice',
  outputs: [{
    locking_script: '76a914...88ac',
    satoshis: 1000,
    output_description: 'Payment',
    basket: 'payments',
    tags: ['invoice-42']
  }],
  options: { auto_fund: true }
)

result[:txid]  # => "abc123..."
```

## Architecture

The wallet is built around five pluggable interfaces under `BSV::Wallet::Interface::`:

| Interface | What it defines | Shipped implementations |
|-----------|----------------|------------------------|
| [BRC100](../wallet/client.md) | 28 wallet methods (transactions, crypto, certificates, etc.) | `Client` |
| [Store](../wallet/store.md) | Persistence for actions, outputs, certificates, proofs | `Store::Memory` (tests), `Store::File` (default), `PostgresStore` ([separate gem](wallet-postgres.md)) |
| [BroadcastQueue](../wallet/broadcast-queue.md) | Transaction dispatch to the network | `BroadcastQueue::Inline` (default), `SolidQueueAdapter` ([separate gem](wallet-postgres.md)) |
| [ProofStore](../wallet/proof-store.md) | SPV merkle proof persistence | `LocalProofStore` |
| [UTXOPool](../wallet/utxo-pool.md) | Pre-funded output pools | `LocalPool` |

Every collaborator has a sensible default. `Client.new(key)` gives you a working wallet backed by JSON files on disk. For production, swap in `PostgresStore` and a broadcaster.

## Constructor

```ruby
BSV::Wallet::Client.new(
  key,                              # PrivateKey, WIF string, or KeyDeriver
  storage: Store::File.new,         # see Store docs
  broadcaster: nil,                 # responds to #broadcast(tx) — e.g. ARC.default
  broadcast_queue: nil,             # defaults to BroadcastQueue::Inline
  proof_store: nil,                 # defaults to LocalProofStore backed by storage
  network: 'mainnet',              # 'mainnet' or 'testnet'
  fee_estimator: nil,              # defaults to FeeEstimator (100 sat/kB)
  coin_selector: nil,              # defaults to CoinSelector (:standard strategy)
  change_generator: nil,           # defaults to ChangeGenerator
  substrate: nil                   # remote wallet — delegates all 28 methods
)
```

## Status lifecycle

Each action carries a `status` field:

| Status | Meaning |
|--------|---------|
| `'nosend'` | Built but not broadcast (`options: { no_send: true }`) |
| `'sending'` | Queued for background broadcast (async adapter) |
| `'unproven'` | Broadcast succeeded; awaiting merkle proof |
| `'completed'` | Merkle proof received and stored |
| `'failed'` | Broadcast rejected by the network |

To find all successfully-broadcast actions, query for both `'unproven'` and `'completed'`.

## Error handling

| Error class | When |
|-------------|------|
| `InsufficientFundsError` | Not enough spendable UTXOs |
| `WalletError` | General wallet operation failure |
| `InvalidParameterError` | Invalid arguments to a wallet method |
| `UnsupportedActionError` | Requested operation not supported |
| `PoolDepletedError` | UTXO pool exhausted |

## Further reading

- [Client (BRC-100)](../wallet/client.md) — the 28 methods, auto-funding, substrate delegation
- [Store](../wallet/store.md) — persistence interface, output state lifecycle, custom adapters
- [Broadcast Queue](../wallet/broadcast-queue.md) — transaction dispatch, sync/async patterns
- [Proof Store](../wallet/proof-store.md) — SPV merkle proof persistence
- [UTXO Pool](../wallet/utxo-pool.md) — pre-funded output pools for high-frequency use
- [Wallet Postgres](wallet-postgres.md) — production PostgreSQL storage and async broadcast
