# bsv-wallet-postgres

PostgreSQL-backed storage and broadcast adapters for [`bsv-wallet`][wallet].
Persistent, multi-instance-safe, and thread-safe via Sequel's connection pool.

`bsv-wallet` ships with two in-process stores: `Store::Memory` (testing only —
data lost on exit) and `Store::File` (JSON on disk, the default). Neither works
across multiple wallet instances sharing state, and `Store::File` is only as
durable as its volume. `bsv-wallet-postgres` fills that gap.

## Installation

```ruby
# Gemfile
gem 'bsv-wallet'
gem 'bsv-wallet-postgres'
```

Pulls in `sequel ~> 5` and `pg ~> 1` as runtime dependencies. The core
`bsv-wallet` gem stays dependency-free.

## Quick start

```ruby
require 'bsv-wallet-postgres'

db = Sequel.connect(ENV['DATABASE_URL'])
BSV::WalletPostgres::PostgresStore.migrate!(db)

store  = BSV::WalletPostgres::PostgresStore.new(db)
wallet = BSV::Wallet::Client.new(
  key,
  storage: store,
  broadcaster: BSV::Network::ARC.default
)
```

`PostgresStore` includes `BSV::Wallet::Interface::Store` — the same contract
that `Store::Memory` and `Store::File` satisfy. Switching from `Store::File` to
`PostgresStore` is a one-line change.

## Schema

Six tables created across migrations 001-006:

| Table | Purpose | Key indexes |
|-------|---------|-------------|
| `wallet_outputs` | UTXOs the wallet is tracking | unique `outpoint`, b-tree `(basket, spendable)`, GIN `tags` |
| `wallet_actions` | BRC-100 actions the wallet created | GIN `labels` |
| `wallet_certificates` | Identity certificates | unique `(type, serial_number, certifier)` |
| `wallet_proofs` | Merkle proofs keyed by txid | primary key `txid` |
| `wallet_transactions` | Raw tx hex cache keyed by txid | primary key `txid` |
| `wallet_broadcast_jobs` | Async broadcast queue (SolidQueueAdapter) | unique `txid`, composite `(status, locked_at)` |

Each table stores the full record as a JSONB blob in a `data` column.
Dedicated indexed columns (`basket`, `tags`, `labels`, `certifier`, etc.)
exist only to make queries fast. Reads always return the JSONB, so
adding fields to `bsv-wallet`'s record hashes does not require a schema
change.

### Running the migration

Migrations live at `lib/bsv/wallet_postgres/migrations/` (001 through 006).
Two ways to apply them:

**Convenience helper** — one-liner, uses `Sequel::Migrator` under the
hood:

```ruby
BSV::WalletPostgres::PostgresStore.migrate!(db)
```

**Your own migration runner** — copy the migration files into your app's
`db/migrate/` directory and let your existing framework handle it.

## Production considerations

### Connection pooling

`PostgresStore` holds a reference to the `Sequel::Database` you pass it
— it does not open its own connections:

```ruby
db = Sequel.connect(ENV['DATABASE_URL'], max_connections: 16)
```

Rule of thumb: `max_connections` should match the wallet's concurrency
ceiling (e.g. Puma worker count x threads per worker).

### Multi-instance deployments

Nothing in `PostgresStore` is per-process state. Two or more wallet
instances can safely share the same database. Outputs upsert on
`outpoint`, certificates upsert on `(type, serial_number, certifier)`,
and proofs/transactions upsert on `txid`.

### Backups

Standard Postgres tooling — `pg_dump`, point-in-time recovery, logical
replication. The wallet has no additional state outside the database.

### Thread safety

`PostgresStore` is thread-safe because Sequel is. The adapter holds no
mutable state beyond the injected database handle.

### What it does **not** do

- **No dialect abstraction.** Postgres-specific by design. SQLite, MySQL,
  or Redis backends belong in sibling gems.
- **No connection management.** You bring your own `Sequel::Database`.
- **No caching layer.** Reads hit the database every time.
- **No automatic migrations.** Call `migrate!` explicitly before first use.

## Async broadcast queue

`SolidQueueAdapter` provides background transaction broadcasting backed
by the `wallet_broadcast_jobs` table. It includes
`BSV::Wallet::Interface::BroadcastQueue` — the same contract that
`BroadcastQueue::Inline` satisfies.

### Setup

```ruby
adapter = BSV::WalletPostgres::SolidQueueAdapter.new(
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
```

### How it works

1. `create_action` with `accept_delayed_broadcast: true` calls
   `adapter.enqueue(payload)` — inserts a row with status `unsent`,
   returns immediately.
2. Background worker polls every 8 seconds (configurable via
   `poll_interval:`), claims a job using `SELECT ... FOR UPDATE SKIP LOCKED`,
   broadcasts via ARC.
3. On success: inputs promoted to `spent`, change to `spendable`, action
   to `completed`.
4. On failure: inputs rolled back to `spendable`, change deleted, action
   marked `failed`.

### Recovery

Stale `sending` jobs (locked but not completed within 5 minutes) are
automatically retried on the next poll. Jobs that fail 5 times
(`MAX_ATTEMPTS`) are left in `failed` state.

### Shutdown

```ruby
adapter.drain  # stops the worker, blocks until current cycle completes
```

### Multi-process safety

`FOR UPDATE SKIP LOCKED` ensures multiple workers each claim different
jobs. No external coordination needed.

### Guards

- Refuses to attach when storage is `Store::Memory` (raises `ArgumentError`)
- Requires a `broadcaster` (raises `ArgumentError` if `nil`)
- Idempotent enqueue: duplicate `txid` returns the existing job's status

## Further reading

- [Store interface](../wallet/store.md) — the contract `PostgresStore` implements
- [Broadcast Queue interface](../wallet/broadcast-queue.md) — the contract `SolidQueueAdapter` implements
- [Wallet gem](wallet.md) — the core wallet documentation

[wallet]: https://github.com/sgbett/bsv-ruby-sdk
