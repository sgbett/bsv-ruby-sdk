# bsv-wallet

BRC-100 wallet interface for the BSV Blockchain. Implements the standard
wallet-to-application interface: `create_action`, `sign_action`,
`list_actions`, `list_outputs`, certificates, and more.

Part of the [BSV Ruby SDK](https://github.com/sgbett/bsv-ruby-sdk)
monorepo.

## Installation

```ruby
# Gemfile
gem 'bsv-wallet'
```

## Quick start

```ruby
require 'bsv-wallet'

key = BSV::Primitives::PrivateKey.from_wif(ENV['SERVER_WIF'])
wallet = BSV::Wallet::WalletClient.new(key)

# Create a simple payment
result = wallet.create_action({
  description: 'Pay invoice',
  outputs: [{
    locking_script: '76a914...88ac',
    satoshis: 1000,
    output_description: 'Payment'
  }]
})
```

## Broadcasting

Pass a broadcaster to enable on-chain broadcast:

```ruby
wallet = BSV::Wallet::WalletClient.new(
  key,
  broadcaster: BSV::Network::ARC.default
)
```

The wallet handles transaction construction, UTXO management, signing,
broadcasting, and state promotion/rollback automatically.

## Storage adapters

| Adapter | Gem | Use case |
|---------|-----|----------|
| `MemoryStore` | bsv-wallet | Tests only |
| `FileStore` | bsv-wallet | Development (default) |
| `PostgresStore` | [bsv-wallet-postgres](https://rubygems.org/gems/bsv-wallet-postgres) | Production |

## Status values

Each action stored by the wallet carries one of the following status values:

| Status | Meaning |
|--------|---------|
| `'nosend'` | Transaction built but not broadcast (caller opted into `options: { no_send: true }`) |
| `'sending'` | Broadcast queued for background processing (async adapter); worker has not yet attempted broadcast |
| `'unproven'` | Broadcast succeeded; awaiting merkle proof |
| `'completed'` | Merkle proof received and stored |
| `'failed'` | Broadcast attempted and rejected by the network |

## Broadcaster requirement

A broadcaster is required for `create_action` to succeed unless
`options: { no_send: true }` is passed per call. Three ways to satisfy this:

1. Pass `broadcaster:` to `WalletClient.new`:
   ```ruby
   wallet = BSV::Wallet::WalletClient.new(key, broadcaster: BSV::Network::ARC.default)
   ```
2. Pass a `broadcast_queue:` whose adapter has an embedded `broadcaster:`:
   ```ruby
   adapter = BSV::Wallet::SolidQueueAdapter.new(db: db, storage: store, broadcaster: arc)
   wallet = BSV::Wallet::WalletClient.new(key, storage: store, broadcast_queue: adapter)
   ```
3. Pass `options: { no_send: true }` to skip broadcast for a specific call:
   ```ruby
   wallet.create_action({ description: '...', outputs: [...], options: { no_send: true } })
   ```

Without one of these, `create_action` raises `BSV::Wallet::WalletError`.

## Documentation

- [Full documentation](https://sgbett.github.io/bsv-ruby-sdk/)
- [Getting started guide](https://sgbett.github.io/bsv-ruby-sdk/guides/getting-started/)
- [Wallet guide](https://sgbett.github.io/bsv-ruby-sdk/guides/wallet/)
- [API reference](https://sgbett.github.io/bsv-ruby-sdk/reference/)
- [Changelog](CHANGELOG.md)

## Licence

[Open BSV Licence Version 5](LICENSE)
