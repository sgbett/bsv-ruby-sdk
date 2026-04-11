# Changelog — bsv-wallet-postgres

All notable changes to the `bsv-wallet-postgres` gem are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this gem adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
