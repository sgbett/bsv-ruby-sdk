# bsv-wallet-postgres

PostgreSQL-backed storage adapter for [`bsv-wallet`][wallet]. Persistent,
multi-instance-safe, and thread-safe via Sequel's connection pool.

`bsv-wallet` ships with two in-process stores: `MemoryStore` (volatile,
for tests) and `FileStore` (JSON on disk at `~/.bsv-wallet/`, the default).
Neither survives a Docker container with an ephemeral volume, and neither
works across multiple wallet instances sharing state. `bsv-wallet-postgres`
fills that gap.

## Installation

```ruby
# Gemfile
gem 'bsv-wallet'
gem 'bsv-wallet-postgres'
```

`bsv-wallet-postgres` pulls in `sequel ~> 5` and `pg ~> 1` as runtime
dependencies. The core `bsv-wallet` gem stays dependency-free — you only
pay for Sequel and libpq if you opt in.

## Quickstart

```ruby
require 'bsv-wallet-postgres'

db = Sequel.connect(ENV['DATABASE_URL'])
BSV::Wallet::PostgresStore.migrate!(db)

store  = BSV::Wallet::PostgresStore.new(db)
wallet = BSV::Wallet::WalletClient.new(
  private_key,
  storage: store,
  chain_provider: your_chain_provider
)
```

That's the whole integration. `WalletClient` already takes any object
that includes `BSV::Wallet::StorageAdapter`, so switching from `FileStore`
to `PostgresStore` is a one-line change.

## Schema

Six tables created across migrations 001–006:

| Table                 | Purpose                             | Key indexes                                       |
|-----------------------|-------------------------------------|---------------------------------------------------|
| `wallet_outputs`      | UTXOs the wallet is tracking        | unique `outpoint`, b-tree `(basket, spendable)`, GIN `tags` |
| `wallet_actions`      | BRC-100 actions the wallet created  | GIN `labels`                                      |
| `wallet_certificates` | Identity certificates               | unique `(type, serial_number, certifier)`         |
| `wallet_proofs`       | Merkle proofs keyed by txid         | primary key `txid`                                |
| `wallet_transactions` | Raw tx hex cache keyed by txid      | primary key `txid`                                |
| `wallet_broadcast_jobs` | Async broadcast queue (SolidQueueAdapter) | unique `txid`, composite `(status, locked_at)` |

Each table stores the full record as a JSONB blob in a `data` column.
Dedicated indexed columns (`basket`, `tags`, `labels`, `certifier`, ...)
exist only to make queries fast. Reads always return the JSONB, so
adding fields to `bsv-wallet`'s record hashes does not require a schema
change.

### Running the migration

Migrations live at `lib/bsv/wallet_postgres/migrations/` (001 through 006).
Two ways to apply them:

**Convenience helper** — one-liner, uses `Sequel::Migrator` under the
hood so the database tracks applied versions:

```ruby
BSV::Wallet::PostgresStore.migrate!(db)
```

**Your own migration runner** — copy the migration file into your app's
`db/migrate/` directory (or wherever you keep them) and let your
existing migration framework handle it. Useful if you want to coordinate
wallet schema changes alongside application schema changes in a single
release.

## Production considerations

### Connection pooling

`PostgresStore` holds a reference to the `Sequel::Database` you pass it
— it does not open its own connections. Size the pool at connection
time:

```ruby
db = Sequel.connect(ENV['DATABASE_URL'], max_connections: 16)
```

Rule of thumb: `max_connections` should match the wallet's concurrency
ceiling (e.g. Puma worker count × threads per worker). Sequel will
block callers waiting for a free connection once the pool is saturated.

### Multi-instance deployments

Nothing in `PostgresStore` is per-process state — two or more wallet
instances can safely share the same database. Outputs upsert on
`outpoint`, certificates upsert on `(type, serial_number, certifier)`,
and proofs/transactions upsert on `txid`, so concurrent writes converge
correctly rather than erroring or duplicating.

### Backups

Standard Postgres tooling — `pg_dump`, point-in-time recovery, logical
replication. The wallet has no additional state outside the database
(unlike `FileStore`, which scatters JSON across a directory).

### Thread safety

`PostgresStore` is thread-safe because Sequel is. The adapter holds no
mutable state beyond the injected database handle. This is an upgrade
over `MemoryStore`, which is explicitly not thread-safe.

### What it does **not** do

- **No dialect abstraction.** This is a Postgres-specific gem by
  design. SQLite, MySQL, or Redis backends belong in sibling gems.
- **No connection management.** You bring your own `Sequel::Database`;
  the adapter never reconnects, never retries, never manages pool
  lifecycle.
- **No caching layer.** Reads hit the database every time. Add caching
  at the application layer if you need it.
- **No automatic migrations on `PostgresStore.new`.** You must call
  `migrate!` (or run the migration yourself) explicitly before first
  use. Clear error on the first query if tables are missing.

## Async broadcast queue

The `SolidQueueAdapter` provides background transaction broadcasting backed
by the `wallet_broadcast_jobs` table. Transactions are enqueued immediately
and broadcast by a background worker thread — the caller doesn't block on
ARC round-trips.

### Setup

```ruby
require 'bsv-wallet-postgres'

db    = Sequel.connect(ENV['DATABASE_URL'])
store = BSV::Wallet::PostgresStore.new(db)

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
```

### How it works

1. `create_action` with `accept_delayed_broadcast: true` calls
   `adapter.enqueue(payload)` which inserts a row into
   `wallet_broadcast_jobs` with status `unsent` and returns immediately.
2. The background worker polls every 8 seconds (configurable via
   `poll_interval:`), claims a job using `SELECT ... FOR UPDATE SKIP LOCKED`,
   and broadcasts via ARC.
3. On success: inputs promoted to `spent`, change to `spendable`, action to
   `completed`.
4. On failure: inputs rolled back to `spendable`, change outputs deleted,
   action marked `failed`.

### Recovery

Stale `sending` jobs (locked but not completed within 5 minutes) are
automatically retried on the next poll. No special startup code is needed —
the worker's first poll finds and reprocesses any stale jobs from a previous
crash.

Jobs that fail 5 times (`MAX_ATTEMPTS`) are left in `failed` state and not
retried.

### Shutdown

```ruby
adapter.drain  # stops the worker and blocks until the current cycle completes
```

Jobs enqueued after `drain` is called remain `unsent` until the next
`adapter.start`.

### Multi-process safety

`FOR UPDATE SKIP LOCKED` ensures that multiple worker processes polling the
same database each claim different jobs. No external coordination is needed.

### Guards

- Refuses to attach when storage is `MemoryStore` (raises `ArgumentError`)
- Requires a `broadcaster` (raises `ArgumentError` if `nil`)
- Idempotent enqueue: duplicate `txid` returns the existing job's status
  instead of raising

## Relationship to `bsv-wallet`

`bsv-wallet-postgres` is a drop-in implementation of
`BSV::Wallet::StorageAdapter` — the same interface `MemoryStore` and
`FileStore` satisfy. The full conformance suite in
`spec/support/shared_examples_for_storage_adapter.rb` runs against all
three backends on every CI build, so behaviour stays aligned.

Versioning tracks `bsv-wallet`: the gemspec pins `bsv-wallet >= 0.6.0,
< 1.0` so consumers pick up wallet security patches automatically.

[wallet]: https://github.com/sgbett/bsv-ruby-sdk
