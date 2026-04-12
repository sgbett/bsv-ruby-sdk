# Changelog — bsv-wallet-postgres

All notable changes to the `bsv-wallet-postgres` gem are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this gem adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.4.0 — 2026-04-12

### Added
- `BSV::Wallet::SolidQueueAdapter` — PostgreSQL-backed async broadcast queue implementing the `BroadcastQueue` interface
- Migration 006: `wallet_broadcast_jobs` table with `FOR UPDATE SKIP LOCKED` polling support
- Background worker thread broadcasts transactions and promotes/rolls back wallet state
- Recovery on restart via stale `locked_at` detection
- Idempotent enqueue on duplicate txid (crash recovery)
- `MAX_ATTEMPTS` enforcement (5) prevents infinite retry loops
- Guard refuses MemoryStore attachment

### Fixed
- Migration timestamps use `timestamptz` (matching migration 004 pattern)
- `start()` check-and-set is atomic under mutex (prevents TOCTOU double-spawn)
- Deserialization failures mark job as failed immediately (no tight retry loop)

## 0.3.1 — 2026-04-12

### Fixed
- `update_action_status` now scopes to a single row by primary key, preventing unintended multi-row updates when duplicate txids exist
- Added migration 005: unique index on `wallet_actions.txid` enforcing one action per transaction

## 0.3.0 — 2026-04-12

### Added
- `update_action_status` and `delete_action` implementations for PostgresStore,
  matching the new StorageAdapter contract introduced in bsv-wallet 0.6.0 (#370)

## 0.2.0 — 2026-04-12

### Added

- **Migration 004** — adds `satoshis`, `pending_since`, `pending_reference`,
  `no_send` columns and a partial index on `(state, basket)` for spendable
  rows (#353)
- **`find_spendable_outputs(basket:, min_satoshis:, sort_order:)`** — query
  spendable outputs with backward-compatible COALESCE for legacy rows (#354)
- **`update_output_state(outpoint, new_state, ...)`** — transition output
  state with JSONB data synchronisation (#354)
- **`lock_utxos(outpoints, reference:, no_send:)`** — atomic
  `UPDATE ... WHERE state = 'spendable' RETURNING` pattern for concurrent
  safety (#355)
- **`release_stale_pending!(timeout:)`** — recover stuck pending outputs,
  exempting `no_send` locks (#355)
- **PostgresStore settings methods** — `store_setting` / `find_setting`

### Fixed

- **Spendable boolean sync** — `update_output_state`, `lock_utxos`, and
  `release_stale_pending!` now keep the legacy `spendable` column in sync
  with the `state` column; `filter_outputs` uses dual-column WHERE clause

### Changed

- Directory restructure — source moved to `gem/bsv-wallet-postgres/`

## 0.1.0 — 2026-04-09

Initial release of `bsv-wallet-postgres`, a PostgreSQL-backed
`BSV::Wallet::StorageAdapter` implementation. Unblocks production
deployments of `bsv-wallet` where state has to survive container
restarts, and makes multi-instance wallet services possible for the
first time.

### Added

- **`BSV::Wallet::PostgresStore`** — full
  `StorageAdapter` implementation over Sequel + Postgres. Passes the
  same shared conformance suite that MemoryStore and FileStore pass
  (53 examples), plus 10 postgres-specific specs covering upsert
  semantics, GIN tag queries, JSONB attribute containment, concurrent
  inserts, and migration idempotency.

- **Shipped Sequel migration** at
  `lib/bsv/wallet_postgres/migrations/001_create_wallet_tables.rb`.
  Five tables (wallet_outputs, wallet_actions, wallet_certificates,
  wallet_proofs, wallet_transactions) with JSONB data columns,
  dedicated indexed columns for filter paths, and GIN indexes on the
  `tags` / `labels` arrays.

- **`PostgresStore.migrate!(db)`** convenience
  wrapper over `Sequel::Migrator.run` so consumers can apply the
  shipped schema with a single call. Operators who prefer their own
  migration framework can copy the migration file instead.

- **Docs** at `docs/guides/wallet-postgres.md` with
  a 30-second quickstart, schema overview, and production
  considerations (pool sizing, multi-instance, backups,
  thread-safety).

### Infrastructure

- **CI postgres service**. The GitHub Actions test job now runs a
  Postgres 16 container and exposes `DATABASE_URL` to rspec, so the
  `:postgres`-tagged specs run against a live database on every
  Ruby matrix row (2.7 → 3.4). Local developers without Postgres
  still get a green suite — those specs skip gracefully.

### Dependencies

- `bsv-wallet-postgres` runtime: `bsv-wallet >= 0.3.4, < 1.0`,
  `sequel ~> 5`, `pg ~> 1`. The wallet floor matches the pinning style
  `bsv-wallet` uses for its `bsv-sdk` dependency so security releases
  propagate.
