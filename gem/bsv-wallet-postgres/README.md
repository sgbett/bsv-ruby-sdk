# bsv-wallet-postgres

PostgreSQL storage adapter for
[bsv-wallet](https://rubygems.org/gems/bsv-wallet). Persistent,
multi-instance-safe, and thread-safe via Sequel's connection pool.

Part of the [BSV Ruby SDK](https://github.com/sgbett/bsv-ruby-sdk)
monorepo.

## Installation

```ruby
# Gemfile
gem 'bsv-wallet-postgres'
```

Requires `pg` and `sequel` (pulled in automatically).

## Quick start

```ruby
require 'bsv-wallet-postgres'

db = Sequel.connect(ENV['DATABASE_URL'])
BSV::Wallet::PostgresStore.migrate!(db)

store  = BSV::Wallet::PostgresStore.new(db)
wallet = BSV::Wallet::WalletClient.new(key, storage: store)
```

## Async broadcast queue

The `SolidQueueAdapter` provides background transaction broadcasting
backed by a PostgreSQL job table:

```ruby
adapter = BSV::Wallet::SolidQueueAdapter.new(
  db: db,
  storage: store,
  broadcaster: BSV::Network::ARC.default
)
adapter.start

wallet = BSV::Wallet::WalletClient.new(
  key,
  storage: store,
  broadcast_queue: adapter
)

# Transactions are enqueued and broadcast in the background.
# On shutdown:
adapter.drain
```

Features: stale job recovery, `FOR UPDATE SKIP LOCKED` multi-process
safety, idempotent enqueue, configurable poll interval and retry limits.

## Documentation

- [Full documentation](https://sgbett.github.io/bsv-ruby-sdk/)
- [Wallet Postgres guide](https://sgbett.github.io/bsv-ruby-sdk/guides/wallet-postgres/)
- [Changelog](CHANGELOG.md)

## Licence

[Open BSV Licence Version 5](LICENSE)
