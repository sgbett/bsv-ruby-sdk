# Plan: HLR #403 — SolidQueueAdapter for bsv-wallet-postgres

## Context

Phase 1 (#380) delivered the pluggable `BroadcastQueue` interface and synchronous `InlineQueue` default. Phase 2 delivers `SolidQueueAdapter` — a PostgreSQL-backed async adapter so `accept_delayed_broadcast: true` actually defers broadcast to a background worker thread.

The adapter uses the same pattern as PostgresStore: caller owns the `Sequel::Database`, adapter is stateless beyond its dependencies. A background `Thread` polls a `wallet_broadcast_jobs` table, broadcasts transactions, and promotes/rolls back wallet state using the same logic as `InlineQueue`.

## Architecture

```
WalletClient
  └── @broadcast_queue = SolidQueueAdapter.new(db:, storage:, broadcaster:)
        ├── enqueue(payload)  → INSERT into wallet_broadcast_jobs, return immediately
        ├── poll_once()       → SELECT FOR UPDATE SKIP LOCKED, broadcast, promote/rollback
        └── drain()           → stop + join worker thread
```

## Tasks

### Task 1: Migration 006 — broadcast jobs table

**New file:** `gem/bsv-wallet-postgres/lib/bsv/wallet_postgres/migrations/006_create_broadcast_jobs.rb`

```ruby
create_table(:wallet_broadcast_jobs) do
  primary_key :id, type: :Bignum
  String  :txid,             null: false, unique: true
  String  :status,           null: false, default: 'unsent'   # unsent|sending|completed|failed
  String  :beef_hex,         text: true, null: false
  column  :input_outpoints,  'text[]'                         # nil for finalize path
  column  :change_outpoints, 'text[]'                         # nil for finalize path
  String  :fund_ref
  Integer :attempts,         null: false, default: 0
  String  :last_error,       text: true
  DateTime :locked_at
  DateTime :created_at,      null: false, default: Sequel::CURRENT_TIMESTAMP
  DateTime :updated_at,      null: false, default: Sequel::CURRENT_TIMESTAMP
  index [:status, :locked_at], name: :broadcast_jobs_poll_idx
end
```

Key decisions:
- `beef_hex` stores BEEF as hex (not bytea) — human-readable for debugging, reconstructible via `Transaction.from_beef_hex`
- `text[]` for outpoints matches the existing `tags` column pattern in `wallet_outputs`
- `FOR UPDATE SKIP LOCKED`-friendly via `locked_at` + `status` index (multi-process safe)
- Unique on `txid` prevents duplicate enqueues

### Task 2: SolidQueueAdapter class

**New file:** `gem/bsv-wallet-postgres/lib/bsv/wallet_postgres/solid_queue_adapter.rb`

**Namespace:** `BSV::Wallet::SolidQueueAdapter` (consistent with `BSV::Wallet::PostgresStore`)

**Constructor:**
```ruby
def initialize(db:, storage:, broadcaster:, poll_interval: 8)
```
- Raises `ArgumentError` if `storage.is_a?(BSV::Wallet::MemoryStore)` (MemoryStore guard)
- Raises `ArgumentError` if `broadcaster.nil?` (async without broadcaster is meaningless)
- Shares the same `db` as PostgresStore — Sequel's connection pool is thread-safe

**Public methods:**

| Method | Behaviour |
|--------|-----------|
| `async?` | Returns `true` |
| `enqueue(payload)` | INSERT into `wallet_broadcast_jobs` with status `'unsent'`; returns `{ txid:, broadcast_status: 'sending' }` |
| `status(txid)` | `@db[:wallet_broadcast_jobs].where(txid:).get(:status)` |
| `start` | Spawns `@worker_thread` with polling loop |
| `stop` | Sets `@running = false` (non-blocking) |
| `drain` | Sets `@running = false` + `@worker_thread.join` (blocks until done) |

**Worker loop (`poll_once` private):**
1. `SELECT ... WHERE status = 'unsent' OR (status = 'sending' AND locked_at < NOW() - 300s) ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED`
2. Mark row as `'sending'`, set `locked_at`, increment `attempts`
3. Reconstruct tx via `Transaction.from_beef_hex(job[:beef_hex])`
4. Call `@broadcaster.broadcast(tx)`
5. **Success:** promote state (inputs → spent, change → spendable, action → completed), mark job `'completed'`
6. **Failure:** rollback state (release inputs matching fund_ref, delete change, action → failed), mark job `'failed'` with `last_error`

**Promote/rollback** are private methods duplicating InlineQueue's ~8-line implementations. Both operate through `@storage` calls which are individually atomic at the SQL level. No wrapping DB transaction needed — if process crashes mid-promote, recovery re-broadcasts (idempotent via ARC) and re-promotes (already-spent is a no-op).

**Recovery:** On `start`, the worker's first poll naturally finds stale `'sending'` jobs via the `locked_at < threshold` clause. No special recovery code needed.

**Thread safety:** `@mutex` protects `@running` flag. All DB access goes through Sequel's thread-safe connection pool. `FOR UPDATE SKIP LOCKED` prevents two poll threads from claiming the same job.

### Task 3: Autoload registration

**Modify:** `gem/bsv-wallet-postgres/lib/bsv/wallet_postgres.rb`

Add one line:
```ruby
module Wallet
  autoload :PostgresStore, 'bsv/wallet_postgres/postgres_store'
  autoload :SolidQueueAdapter, 'bsv/wallet_postgres/solid_queue_adapter'  # NEW
end
```

### Task 4: Test helper update

**Modify:** `gem/bsv-wallet-postgres/spec/support/postgres_helper.rb`

Add `wallet_broadcast_jobs` to `POSTGRES_WALLET_TABLES` for per-test cleanup.

### Task 5: Specs

**New file:** `gem/bsv-wallet-postgres/spec/bsv/wallet_postgres/solid_queue_adapter_spec.rb`

Coverage map (maps to acceptance criteria):

| Spec group | AC |
|------------|-----|
| Constructor raises for MemoryStore | Guard: refuses to attach when storage is MemoryStore |
| Constructor raises for nil broadcaster | Constructor validation |
| `async?` returns `true` | `async?` returns `true` |
| `enqueue` inserts row, returns `{ broadcast_status: 'sending' }` | `enqueue` persists to PG, returns status |
| `enqueue` handles nil outpoints (finalize path) | Finalize path support |
| Concurrent enqueue from multiple threads (unique txid) | Thread safety |
| `status` returns status / nil | `status(txid)` returns broadcast status |
| Worker success: promotes inputs, change, action | Worker promotes on success |
| Worker failure: rolls back inputs, change, action, sets last_error | Worker rolls back on failure |
| Worker finalize path (nil outpoints) | Both paths covered |
| Stale 'sending' job retried on poll | Recovery on restart |
| `drain` blocks until worker finishes | Graceful shutdown |
| Existing specs pass | Run full suite |

Test strategy: Use real PostgreSQL (same `postgres_helper.rb` pattern), mock broadcaster, real PostgresStore. Start/drain worker within each test to avoid thread leaks.

## Critical files

| File | Action |
|------|--------|
| `gem/bsv-wallet-postgres/lib/bsv/wallet_postgres/migrations/006_create_broadcast_jobs.rb` | Create |
| `gem/bsv-wallet-postgres/lib/bsv/wallet_postgres/solid_queue_adapter.rb` | Create |
| `gem/bsv-wallet-postgres/lib/bsv/wallet_postgres.rb` | Modify (add autoload) |
| `gem/bsv-wallet-postgres/spec/support/postgres_helper.rb` | Modify (add table) |
| `gem/bsv-wallet-postgres/spec/bsv/wallet_postgres/solid_queue_adapter_spec.rb` | Create |

## Reference files (read-only)

| File | Why |
|------|-----|
| `gem/bsv-wallet/lib/bsv/wallet_interface/broadcast_queue.rb` | Interface contract |
| `gem/bsv-wallet/lib/bsv/wallet_interface/inline_queue.rb` | Promote/rollback reference |
| `gem/bsv-wallet-postgres/lib/bsv/wallet_postgres/postgres_store.rb` | DB patterns, Sequel conventions |
| `gem/bsv-wallet-postgres/spec/support/postgres_helper.rb` | Test helper pattern |

## Verification

```bash
cd /opt/ruby/bsv-ruby-sdk
bundle exec rake spec:wallet            # Existing wallet specs still pass
cd gem/bsv-wallet-postgres
bundle exec rspec spec/bsv/wallet_postgres/solid_queue_adapter_spec.rb  # New specs pass
bundle exec rspec                        # All postgres specs pass
cd /opt/ruby/bsv-ruby-sdk
bundle exec rubocop gem/bsv-wallet-postgres/  # Clean
```

## Sequencing

```
Task 1 (migration) ──→ Task 2 (adapter class) ──→ Task 5 (specs)
Task 3 (autoload)  ──  independent, parallel with Task 2
Task 4 (test helper) ── independent, must precede Task 5
```
