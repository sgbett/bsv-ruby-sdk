# bsv-wallet-postgres — persistent StorageAdapter backend

**Issue:** #297
**Branch:** `worktree-297-bsv-wallet-postgres`
**Status:** Planned, awaiting implementation start

## Problem

`bsv-wallet` ships with `MemoryStore` and `FileStore`. The default wallet
constructor (`WalletClient.new(key, storage: FileStore.new)`) persists to
`~/.bsv-wallet/` — fine locally, fatal in any Docker-with-ephemeral-volume
deployment. x402-doom is blocked in production by this: every container
restart wipes UTXOs, actions, certificates, and proofs, forcing a full
resync from chain.

A persistent, process-independent, multi-instance-safe storage adapter is
a hard prerequisite for any real deployment of `bsv-wallet`.

## Solution overview

Ship `bsv-wallet-postgres` as a **fourth gem** from this monorepo, mirroring
the `bsv-attest` / `bsv-wallet` pattern. Provides `BSV::Wallet::PostgresStore`,
a thin Sequel-backed implementation of `BSV::Wallet::StorageAdapter` optimised
for Postgres features (jsonb for round-trip fidelity, GIN indexes on tag/label
arrays, composite unique upserts).

Core `bsv-wallet` stays dependency-free. Consumers opt in by adding
`gem 'bsv-wallet-postgres'` to their Gemfile. A sibling gem (sqlite, redis)
can follow the same pattern later if demand appears.

## Correction to HLR

The HLR suggests file path `lib/bsv/wallet/postgres_store.rb`. **This is
wrong.** `lib/bsv/wallet/` is already packaged in `bsv-sdk` (via the glob
`{primitives,script,transaction,network,wallet,...}` in `bsv-sdk.gemspec`)
for `BSV::Wallet::Wallet` — the imperative P2PKH funder at
`lib/bsv/wallet/wallet.rb`. Adding `postgres_store.rb` there would vendor
it into `bsv-sdk`.

**Correct layout** mirrors `bsv-wallet`'s own pattern:

```
lib/bsv-wallet-postgres.rb                          # entry point
lib/bsv/wallet_postgres.rb                          # autoloads
lib/bsv/wallet_postgres/version.rb                  # BSV::WalletPostgres::VERSION
lib/bsv/wallet_postgres/postgres_store.rb           # class body
lib/bsv/wallet_postgres/migrations/001_create_wallet_tables.rb
```

Class namespace remains `BSV::Wallet::PostgresStore` (module reopened,
same home as `MemoryStore` and `FileStore`).

## Phase 0 — Prerequisite: extract shared conformance suite

The HLR says "Run bsv-wallet's existing StorageAdapter conformance specs
against PostgresStore". **That suite doesn't exist.**
`spec/bsv/wallet_interface/storage_adapter_spec.rb` only checks
`NotImplementedError`. All behavioural coverage is inlined in
`memory_store_spec.rb`. Without extraction, Phase 3 becomes copy-paste.

### Work
1. Create `spec/support/shared_examples_for_storage_adapter.rb`. Lift the
   behaviour specs out of `memory_store_spec.rb` as
   `RSpec.shared_examples 'a storage adapter'`.
2. `memory_store_spec.rb` → `it_behaves_like 'a storage adapter'` plus any
   MemoryStore-specific tests.
3. `file_store_spec.rb` → add `it_behaves_like 'a storage adapter'`
   alongside its persistence-specific tests (free coverage win).
4. Document contract points currently ambiguous, either in shared examples
   or in `StorageAdapter` module comments:
   - `store_output` idempotency on `:outpoint` — implementation-defined.
     MemoryStore: append. PostgresStore: upsert. Documented in PostgresStore.
   - `delete_output` hard-deletes (does not flip `spendable: false`).
   - `find_*` returns `[]` not `nil` on empty match.
   - Default `limit: 10`, `offset: 0`.
   - `find_proof` and `find_transaction` return `nil` on miss.

Pure refactor of `bsv-wallet`. Ships as commit 1.

## Phase 1 — Gem skeleton

### 1. `bsv-wallet-postgres.gemspec`

```ruby
require_relative 'lib/bsv/wallet_postgres/version'

Gem::Specification.new do |spec|
  spec.name        = 'bsv-wallet-postgres'
  spec.version     = BSV::WalletPostgres::VERSION
  spec.authors     = ['Simon Bettison']
  spec.summary     = 'PostgreSQL storage adapter for bsv-wallet'
  spec.description = 'Persistent Sequel/Postgres-backed BSV::Wallet::StorageAdapter implementation for production wallet deployments.'
  spec.homepage    = 'https://github.com/sgbett/bsv-ruby-sdk'
  spec.license     = 'LicenseRef-OpenBSV'
  spec.required_ruby_version = '>= 2.7'

  spec.metadata = {
    'homepage_uri' => spec.homepage,
    'source_code_uri' => spec.homepage,
    'changelog_uri' => "#{spec.homepage}/blob/master/CHANGELOG.md",
    'rubygems_mfa_required' => 'true'
  }

  spec.files = Dir.glob('lib/bsv/wallet_postgres{.rb,/**/*}') + %w[lib/bsv-wallet-postgres.rb LICENSE]
  spec.require_paths = ['lib']

  spec.add_dependency 'bsv-wallet', '>= 0.3.4', '< 1.0'
  spec.add_dependency 'sequel', '~> 5'
  spec.add_dependency 'pg', '~> 1'
end
```

### 2. Monorepo wiring

- `Gemfile` — add `gemspec name: 'bsv-wallet-postgres'`
- `Gemfile` dev/test group — add `database_cleaner-sequel` (verify 2.7 support first)
- `Rakefile` — add `Bundler::GemHelper.install_tasks(name: 'bsv-wallet-postgres')`

### 3. Gemspec disjointness (verified)

| Gem               | Glob                                                                                 | Matches `lib/bsv/wallet_postgres`? |
|-------------------|--------------------------------------------------------------------------------------|-----------------------------------|
| bsv-sdk           | `lib/bsv/{primitives,script,transaction,network,wallet,auth,overlay,identity,registry}{.rb,/**/*}` | no (brace expansion literal) |
| bsv-wallet        | `lib/bsv/wallet_interface{.rb,/**/*}`                                                | no |
| bsv-attest        | `lib/bsv/attest{.rb,/**/*}`                                                          | no |
| bsv-wallet-postgres | `lib/bsv/wallet_postgres{.rb,/**/*}`                                               | yes (only) |

### 4. Entry points

```ruby
# lib/bsv-wallet-postgres.rb
require 'bsv-wallet'
require_relative 'bsv/wallet_postgres'
```

```ruby
# lib/bsv/wallet_postgres.rb
module BSV
  module WalletPostgres
    autoload :VERSION, 'bsv/wallet_postgres/version'
  end
  module Wallet
    autoload :PostgresStore, 'bsv/wallet_postgres/postgres_store'
  end
end
```

```ruby
# lib/bsv/wallet_postgres/version.rb
module BSV
  module WalletPostgres
    VERSION = '0.1.0'
  end
end
```

## Phase 2 — PostgresStore + migration

### 5. Migration

`lib/bsv/wallet_postgres/migrations/001_create_wallet_tables.rb`

```ruby
Sequel.migration do
  change do
    create_table(:wallet_outputs) do
      primary_key :id
      String :outpoint, null: false, unique: true
      String :basket
      column :tags, 'text[]'
      Boolean :spendable, null: false, default: true
      jsonb :data, null: false
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      index %i[basket spendable]
      index :tags, type: :gin
    end

    create_table(:wallet_actions) do
      primary_key :id
      String :txid, null: false
      column :labels, 'text[]'
      jsonb :data, null: false
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      index :labels, type: :gin
    end

    create_table(:wallet_certificates) do
      primary_key :id
      String :type
      String :serial_number
      String :certifier
      String :subject
      jsonb :data, null: false
      unique %i[type serial_number certifier]
    end

    create_table(:wallet_proofs) do
      String :txid, primary_key: true
      String :bump_hex, text: true, null: false
    end

    create_table(:wallet_transactions) do
      String :txid, primary_key: true
      String :tx_hex, text: true, null: false
    end
  end
end
```

### 6. `PostgresStore.migrate!(db)`

Convenience wrapper over `Sequel::Migrator.run(db, migrations_dir)` that runs
all numbered migration files in `lib/bsv/wallet_postgres/migrations/`. Uses
Sequel's built-in schema versioning so v0.2.0 can add migration 002 without
breaking existing deployments (decision: versioned from day one — see Risk 2).

```ruby
def self.migrate!(db)
  require 'sequel/extensions/migration'
  migrations_dir = File.expand_path('migrations', __dir__)
  Sequel::Migrator.run(db, migrations_dir)
end
```

### 7. `BSV::Wallet::PostgresStore` class

`lib/bsv/wallet_postgres/postgres_store.rb`, ~250 LOC. Key behaviours:

- `initialize(db)` — takes a Sequel `Database`. Consumers bring their own
  connection pool. No `DATABASE_URL` coupling.
- **`include BSV::Wallet::StorageAdapter`** — interface conformance.
- **JSONB key symbolisation**: `pg` returns JSONB as string-keyed hashes.
  `MemoryStore`/`FileStore` use symbol keys. Recursive `symbolise_keys` on
  reads (reuse pattern from `file_store.rb:196`).
- **Tag/label filters**:
  - `'any'` mode (default) → `tags && ARRAY[...]` (overlap)
  - `'all'` mode → `tags @> ARRAY[...]` (contains)
  - GIN index guarantees these are fast.
- **Outputs**: upsert on `:outpoint` via `insert_conflict(target: :outpoint, update: {...})`.
- **Certificates**: upsert on composite `(type, serial_number, certifier)`.
- **Certificate `:attributes` filter**: JSONB containment —
  `data->'fields' @> '{"name":"x"}'::jsonb`. Sequel `pg_jsonb_op#contains`.
- **Proofs/transactions**: upsert on PK (txid).
- **Actions**: append-only (no natural key in the interface).
- **Counts**: never apply pagination — match MemoryStore semantics.
- **Thread-safety**: free via Sequel's connection pool. Documented as an
  upgrade over MemoryStore in the README.
- **No auto-migration**: consumer must call `migrate!` explicitly (see
  Risk 6). Clear error on first query if tables missing.

## Phase 3 — Tests

### 8. Conformance + postgres-specific specs

`spec/bsv/wallet_postgres/postgres_store_spec.rb`:

```ruby
require 'spec_helper'
require 'bsv-wallet-postgres'
require_relative '../../support/postgres_helper'
require_relative '../../support/shared_examples_for_storage_adapter'

RSpec.describe BSV::Wallet::PostgresStore, :postgres do
  let(:db) { POSTGRES_TEST_DB }
  let(:store) { described_class.new(db) }

  before(:all) { described_class.migrate!(POSTGRES_TEST_DB) }
  before(:each) { DatabaseCleaner[:sequel, db: POSTGRES_TEST_DB].clean }

  it_behaves_like 'a storage adapter'

  describe 'postgres-specific behaviour' do
    it 'upserts outputs on outpoint (last-write-wins)'
    it 'supports tag && semantics via GIN index'
    it 'supports tag @> semantics via GIN index'
    it 'upserts certificates on composite unique'
    it 'filters certificates by jsonb containment on fields'
    it 'handles concurrent inserts of the same outpoint'
    it 'PostgresStore.migrate! creates all five tables'
  end
end
```

### 9. Postgres test helper

`spec/support/postgres_helper.rb`:

```ruby
require 'sequel'

POSTGRES_TEST_DB = begin
  Sequel.connect(ENV.fetch('DATABASE_URL')) if ENV['DATABASE_URL']
rescue Sequel::DatabaseConnectionError
  nil
end

RSpec.configure do |config|
  config.before(:each, :postgres) do
    skip 'postgres unavailable (set DATABASE_URL)' unless POSTGRES_TEST_DB
  end
end
```

Tests tagged `:postgres` skip gracefully when `DATABASE_URL` is absent so
local developers running `bundle exec rake` without Postgres still get a
green suite.

## Phase 4 — CI

### 10. GitHub Actions

`.github/workflows/ci.yml` gains a postgres service container on the test job:

```yaml
services:
  postgres:
    image: postgres:16
    env:
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: bsv_wallet_test
    ports: ['5432:5432']
    options: >-
      --health-cmd="pg_isready -U postgres"
      --health-interval=10s
      --health-timeout=5s
      --health-retries=5
```

`env: DATABASE_URL: postgres://postgres:postgres@localhost:5432/bsv_wallet_test`
at the job level. Ruby 2.7 → 3.4 matrix unchanged. Postgres-tagged specs
light up automatically once the service is up.

## Phase 5 — Docs & release

### 11. Documentation

- `docs/gems/wallet-postgres.md` — 30-second quickstart, schema overview,
  production considerations (pool sizing, backups, multi-instance),
  thread-safety note.
- Top-level `README.md` gets a one-line "Persistent storage: see
  `bsv-wallet-postgres`" mention under the wallet section.

Quickstart:

```ruby
require 'bsv-wallet-postgres'

db = Sequel.connect(ENV['DATABASE_URL'])
BSV::Wallet::PostgresStore.migrate!(db)

store = BSV::Wallet::PostgresStore.new(db)
wallet = BSV::Wallet::WalletClient.new(key, storage: store)
```

### 12. CHANGELOG

New `bsv-wallet-postgres v0.1.0` entry. Note the Phase 0 shared-examples
refactor under `bsv-wallet` (no behaviour change, doesn't warrant a version
bump by itself).

### 13. Release

- `gem build bsv-wallet-postgres.gemspec`
- `gem push bsv-wallet-postgres-0.1.0.gem`
- Tag `wallet-postgres-v0.1.0`

## Phase 6 — Out of scope

### 14. x402-doom consumer swap

Happens in the `x402-doom` repo as a separate PR. Replace any ad-hoc
`server/wallet_postgres_store.rb` with `require 'bsv-wallet-postgres'`.
Track as a follow-up issue, not a blocker for this HLR.

## Commit sequence

1. `refactor(wallet): extract StorageAdapter conformance shared examples`
   — Phase 0, zero behaviour change, memory_store_spec and file_store_spec
   both use the shared group.
2. `feat(wallet-postgres): gem skeleton and wiring`
   — Phase 1, rake default still green, gem empty.
3. `feat(wallet-postgres): shipped Sequel migration for wallet tables`
   — Phase 2 items 5–6.
4. `feat(wallet-postgres): implement PostgresStore`
   — Phase 2 item 7, passes shared examples.
5. `test(wallet-postgres): postgres-specific specs`
   — Phase 3.
6. `ci: add postgres service container`
   — Phase 4.
7. `docs(wallet-postgres): quickstart and operations guide`
   — Phase 5.11.
8. `chore: release bsv-wallet-postgres v0.1.0`
   — Phase 5.12–13.

Nothing between commits 1 and 4 breaks master. Commits 5 and 6 together
light up new specs in CI.

## Decisions

1. **JSONB symbolisation** — per-read recursive walk. Simpler than mutating
   Sequel's global pg_json extension state. Perf note in README; revisit
   only if wallets hit millions of rows.

2. **Schema versioning** — use `Sequel::Migrator` from day one, even with
   one migration file. Lets v0.2.0 add migration 002 without a breaking
   conversation with consumers.

3. **Shared examples location** — `spec/support/` (dev-only) for v0.1.0.
   Promote to shipped `lib/` path if/when a third party writes a sibling
   adapter (`bsv-wallet-sqlite`, `bsv-wallet-redis`).

4. **Ruby 2.7 dependencies** — verify `sequel ~> 5`, `pg ~> 1`,
   `database_cleaner-sequel` all support 2.7 before committing Phase 1.

5. **`bsv-wallet` version constraint** — `>= 0.3.4, < 1.0`. Matches house
   style (how `bsv-wallet` pins `bsv-sdk`). Explicit floor rises with every
   wallet security release.

6. **No auto-migration** — `PostgresStore.new` does not mutate schema.
   Requires explicit `migrate!` call. Consumer's migration runner owns DDL.
   Tempting for ergonomics, dangerous in production. Clear error on first
   query if tables don't exist.

## Acceptance criteria (from HLR)

| HLR criterion | Plan phase |
|---|---|
| Gem skeleton: gemspec, Gemfile, README, LICENCE | Phase 1 items 1–4 |
| `BSV::Wallet::PostgresStore` implementing full StorageAdapter | Phase 2 item 7 |
| Shipped migration | Phase 2 item 5 |
| Conformance specs pass against PostgresStore | Phase 0 + Phase 3 item 8 |
| Postgres-specific specs (upsert, tag semantics, concurrency) | Phase 3 item 8 |
| README quickstart | Phase 5 item 11 |
| Published to rubygems | Phase 5 item 13 |

## Size estimate

- Phase 0 shared examples extraction: ~300 LOC moved, ~50 LOC new
- PostgresStore: ~250 LOC
- Migration: ~60 LOC
- Postgres-specific specs: ~150 LOC
- Gemspec, wiring, entry points: ~50 LOC
- CI delta: ~15 lines
- Docs + CHANGELOG: ~200 LOC

**Total:** ~1,000 LOC added, ~300 LOC refactored.

Single reviewable PR, or the 8-commit stack above for stacked review.
