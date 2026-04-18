# Plan: HLR #474 — UTXO Pool Management (REDO at High Effort)

## Context

High-frequency transaction use cases (x420-Doom) are bottlenecked by UTXO contention. This is a redo of the previous implementation which was done at medium effort and had 9 bugs found in review. This time we incorporate BRC-122 (basket namespace framework) from the start and address every known bug proactively.

### Bugs from round 1 (all must be prevented)

| # | Bug | Fix task |
|---|-----|----------|
| 1 | Pool locks lacked `no_send: true` — stale recovery released them at 300s | Task 5 |
| 2 | Basket validator rejected colons in `pool:doom` | Task 1 |
| 3 | Signal off-by-one: `<` should be `<=` for watermark | Task 5 |
| 4 | `store_tracked_outputs` didn't persist derivation metadata | Task 3 |
| 5 | `create_action` keyword-vs-positional-hash in Ruby 3.x | Task 6 |
| 6 | Missing `output_description` on split outputs | Task 6 |
| 7 | Missing `auto_fund: true` on split create_action | Task 6 |
| 8 | Missing `storage` attr_reader on pool | Task 5 |
| 9 | Scavenge TOCTOU race (benign, document only) | Task 2 |

## Tasks

### Task 1: Two-zone basket validation (BRC-122)

**Files:** `gem/bsv-wallet/lib/bsv/wallet_interface/validators.rb`

Replace `validate_basket!` with a two-zone branch:
- Colon present → `validate_structured_basket!`: trim, downcase, 1-300 bytes, valid namespace prefix before colon, content after colon, no consecutive colons/spaces
- No colon → `validate_flat_basket!`: extracted current logic unchanged (5-300 chars, `[a-z0-9 ]`, reserved prefixes)

Key: the structured zone uses characters (`:`+`.`+`-`) that are invalid in BRC-100 flat zone, so zero backwards compatibility risk. Non-implementing wallets reject structured names at the character check.

**Spec additions to `validators_spec.rb`:** `pool:doom` passes, `pool:` fails, `:orphan` fails, `pool::x` fails, case normalisation, existing flat-zone tests unchanged.

### Task 2: `update_output_basket` storage method

**Files:** `storage_adapter.rb` (abstract), `memory_store.rb` (mutex impl), `file_store.rb` (super + save_outputs)

Add `update_output_basket(outpoint, new_basket)` — moves an output between baskets as metadata-only (BRC-66 principle). Raises WalletError if outpoint not found. Document the benign TOCTOU race (bug #9).

**Shared examples:** basket change, return value, not-found error, state preservation.

### Task 3: Fix `store_tracked_outputs` derivation metadata

**File:** `wallet_client.rb` lines 1541-1550

Add `derivation_prefix`, `derivation_suffix`, `sender_identity_key` to the hash passed to `store_output`. These propagate from the output spec — nil for ordinary basket outputs (harmless), present for pool split outputs (essential for later spending via auto-fund).

Do NOT add `state: :spendable` — keep legacy `spendable: true` for backwards compat.

### Task 4: UTXOPool interface + PoolDepletedError

**New files:** `utxo_pool.rb` (module), `errors/pool_depleted_error.rb`
**Modified:** `wallet_interface.rb` (autoloads for UTXOPool, LocalPool, ReplenishmentWorker, PoolDepletedError)

UTXOPool module defines `acquire`, `release`, `status`, `shutdown` — all raise NotImplementedError. Defines `MAX_RETRIES = 3`. Follows BroadcastQueue pattern.

PoolDepletedError < WalletError, takes pool name in constructor.

### Task 5: LocalPool concrete implementation

**New file:** `local_pool.rb`

`class LocalPool; include UTXOPool`

Constructor: `name:, storage:, wallet_client:, target_count:, target_satoshis:, low_water_mark:`
- Basket derived as `"pool:#{name}"` (structured zone)
- `attr_reader :storage, :basket, :name` (bug #8 fix)

`acquire`:
- `find_spendable_outputs(basket:)` → `lock_utxos([outpoint], reference:, no_send: true)` (bug #1 fix)
- Retry up to MAX_RETRIES on contention
- Signal replenisher when `count <= watermark_threshold` (bug #3 fix: `<=` not `<`)
- Raise PoolDepletedError on exhaustion

`release(outpoint)`: `update_output_state(outpoint, :spendable)`

`status`: `{ available:, target:, satoshis_committed:, state: }` — `:healthy`/`:replenishing`/`:depleted`/`:shutdown`

`shutdown`: stop replenisher, idempotent

### Task 6: ReplenishmentWorker

**New file:** `replenishment_worker.rb`

Background Thread with Mutex + ConditionVariable. `start`/`stop`/`signal`.

`replenish`: calculates deficit, builds output specs via `ChangeGenerator#build_output` (gets BRC-29 derivation), converts Script to hex, calls `create_action` with:
- `auto_fund: true` (bug #7 fix)
- `output_description: 'utxo pool replenishment'` (bug #6 fix, 25 chars)
- `basket: pool.basket` (passes structured-zone validation per bug #2 fix)
- Explicit `{...}` hash wrapping (bug #5 fix)
- `derivation_prefix`/`suffix`/`sender_identity_key` on each output spec (bug #4 flows through Task 3 fix)

Error handling: rescue WalletError (log, retry next cycle), rescue StandardError (log, don't crash thread).

### Task 7: WalletClient `utxo_pool` factory

**File:** `wallet_client.rb` (add after `set_wallet_change_params`)

```ruby
def utxo_pool(name:, target_count: 20, target_satoshis: 10_000, low_water_mark: 0.5)
```

Creates LocalPool + ReplenishmentWorker, wires them, starts worker. Returns pool. Caller responsible for `pool.shutdown`.

### Task 8: Comprehensive specs

**New files:** `utxo_pool_spec.rb`, `local_pool_spec.rb`, `replenishment_worker_spec.rb`
**Modified:** `validators_spec.rb`, `shared_examples_for_storage_adapter.rb`

Every bug from round 1 has a regression test:
- Bug #1: acquired output survives `release_stale_pending!`
- Bug #2: `pool:doom` passes validator
- Bug #3: pool-of-1 signals replenisher
- Bug #4: basket outputs persist derivation metadata
- Bug #5-7: create_action args are valid (tested via replenishment worker spec)
- Bug #8: `pool.storage` returns adapter

Plus: concurrent acquire (barrier pattern), status state machine, shutdown idempotency, factory integration.

## Dependency order

```
Tasks 1, 2, 3, 4 — independent, can parallelise
  → Task 5 (depends on 1, 2, 4)
    → Task 6 (depends on 3, 5)
      → Task 7 (depends on 5, 6)
        → Task 8 (depends on all)
```

Recommended sequential: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8

## Verification

```bash
bundle exec rake spec:wallet           # all specs pass
bundle exec rubocop gem/bsv-wallet/    # no offences
```

## Key files

| File | Action | Task |
|------|--------|------|
| `lib/bsv/wallet_interface/validators.rb` | Modify | 1 |
| `lib/bsv/wallet_interface/storage_adapter.rb` | Modify | 2 |
| `lib/bsv/wallet_interface/memory_store.rb` | Modify | 2 |
| `lib/bsv/wallet_interface/file_store.rb` | Modify | 2 |
| `lib/bsv/wallet_interface/wallet_client.rb` | Modify | 3, 7 |
| `lib/bsv/wallet_interface/utxo_pool.rb` | Create | 4 |
| `lib/bsv/wallet_interface/errors/pool_depleted_error.rb` | Create | 4 |
| `lib/bsv/wallet_interface/local_pool.rb` | Create | 5 |
| `lib/bsv/wallet_interface/replenishment_worker.rb` | Create | 6 |
| `lib/bsv/wallet_interface.rb` | Modify | 4 |
| `spec/bsv/wallet_interface/validators_spec.rb` | Modify | 8 |
| `spec/support/shared_examples_for_storage_adapter.rb` | Modify | 8 |
| `spec/bsv/wallet_interface/utxo_pool_spec.rb` | Create | 8 |
| `spec/bsv/wallet_interface/local_pool_spec.rb` | Create | 8 |
| `spec/bsv/wallet_interface/replenishment_worker_spec.rb` | Create | 8 |
