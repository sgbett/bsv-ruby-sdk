# Plan: HLR #380 Phase 1 — BroadcastQueue Interface, InlineQueue, MemoryStore Demotion

## Context

`accept_delayed_broadcast: true` is stubbed — it logs a warning and broadcasts synchronously. The TS SDK uses a full server-side `Monitor` + database-backed state machine, but analysis shows this is over-engineered for Ruby's single-process wallet. The pragmatic approach: a pluggable `BroadcastQueue` interface with an `InlineQueue` default (synchronous), enabling async adapters (SolidQueue, Sidekiq) in follow-up gems.

MemoryStore is simultaneously demoted to test-only since it has no persistence guarantees for production wallet use, and async broadcast requires a persistent storage backend.

**Goal:** Zero functional change for existing consumers. The stubs become real code, the architecture becomes extensible, and the foundation is laid for Phase 2/3 async adapters.

## Architecture

```
WalletClient
  └── @broadcast_queue (BroadcastQueue)
        ├── InlineQueue           (bsv-wallet, default — synchronous)
        ├── SolidQueueAdapter     (bsv-wallet-postgres, Phase 2)
        └── SidekiqAdapter        (bsv-wallet-redis, Phase 3)
```

The queue receives a payload hash containing everything needed to broadcast and promote/rollback. InlineQueue executes immediately; async adapters persist the job for a worker.

## Tasks

### Task 1: BroadcastQueue interface module

**New file:** `gem/bsv-wallet/lib/bsv/wallet_interface/broadcast_queue.rb`

Duck-typed module following the `StorageAdapter` pattern:

```ruby
module BSV::Wallet::BroadcastQueue
  def enqueue(payload)          # => Hash (result)
    raise NotImplementedError, "#{self.class}#enqueue not implemented"
  end

  def async?                    # => Boolean
    false
  end

  def status(txid)              # => String or nil
    raise NotImplementedError, "#{self.class}#status not implemented"
  end

  # Shared helper: map broadcast exceptions to status strings.
  # Moved from WalletClient#broadcast_status_for.
  def self.status_for_error(error)
    return 'serviceError' unless error.is_a?(BSV::Network::BroadcastError)
    arc = error.arc_status.to_s.upcase
    return 'doubleSpend' if arc == 'DOUBLE_SPEND_ATTEMPTED'
    invalid = %w[REJECTED INVALID MALFORMED MINED_IN_STALE_BLOCK]
    return 'invalidTx' if invalid.include?(arc) || arc.include?('ORPHAN')
    'serviceError'
  end
end
```

**Payload contract** (the `enqueue` argument):

```ruby
{
  tx: Transaction,                  # Signed tx object (for InlineQueue)
  txid: String,                     # Hex txid
  beef_binary: String,              # Raw BEEF bytes (for serialisation/return)
  input_outpoints: Array<String>,   # Locked input outpoints (nil for finalize path)
  change_outpoints: Array<String>,  # Change outpoints (nil for finalize path)
  fund_ref: String,                 # Fund reference for rollback (nil for finalize path)
  accept_delayed_broadcast: Boolean # From caller options
}
```

**Add autoload** in `gem/bsv-wallet/lib/bsv/wallet_interface.rb`.

### Task 2: InlineQueue default adapter

**New file:** `gem/bsv-wallet/lib/bsv/wallet_interface/inline_queue.rb`

```ruby
class BSV::Wallet::InlineQueue
  include BSV::Wallet::BroadcastQueue

  def initialize(broadcaster: nil, storage:)
    @broadcaster = broadcaster
    @storage = storage
  end

  def async?
    false
  end

  def status(txid)
    actions = @storage.find_actions({ txid: txid, limit: 1, offset: 0 })
    actions.first&.dig(:status)
  end

  def enqueue(payload)
    if @broadcaster
      broadcast_and_promote(payload)
    else
      promote_without_broadcast(payload)
    end
  end
end
```

`broadcast_and_promote` consolidates the logic currently at `wallet_client.rb:1233-1251`:
- Call `@broadcaster.broadcast(payload[:tx])`
- On success: promote inputs → `:spent`, change → `:spendable`, action → `'completed'`
- On failure: rollback inputs → `:spendable`, delete change outputs, action → `'failed'`
- Return result hash with `:txid`, `:tx`, `:broadcast_result`/`:broadcast_error`, `:broadcast_status`

`promote_without_broadcast` consolidates the no-broadcaster fallback at `wallet_client.rb:733-748`:
- Promote inputs → `:spent`, change → `:spendable`
- Set action status to `'unproven'` if `accept_delayed_broadcast`, else `'completed'`
- Return `{ txid:, tx: }` (BEEF for manual broadcast)

The rollback logic (`release_pending_utxos` pattern) is replicated here (~8 lines) rather than calling back into WalletClient. This avoids circular coupling.

**Add autoload** in `gem/bsv-wallet/lib/bsv/wallet_interface.rb`.

### Task 3: Wire WalletClient to use the queue

**Modify:** `gem/bsv-wallet/lib/bsv/wallet_interface/wallet_client.rb`

**Constructor** (line ~63): Add `broadcast_queue: nil` parameter. Auto-create if not provided:
```ruby
@broadcast_queue = broadcast_queue || InlineQueue.new(
  broadcaster: @broadcaster,
  storage: @storage
)
```

Add `attr_reader :broadcast_queue`.

**Auto-fund path** (lines 729-749): Replace the `if broadcast_enabled? ... else ...` block with:
```ruby
@broadcast_queue.enqueue(
  tx: tx, txid: txid, beef_binary: beef_binary,
  input_outpoints: selected_outpoints,
  change_outpoints: change_outpoints,
  fund_ref: fund_ref,
  accept_delayed_broadcast: args.dig(:options, :accept_delayed_broadcast)
)
```

This eliminates the `accept_delayed_broadcast` stub warning and the manual promote-without-broadcast fallback.

**Finalize path** (lines 1372-1395): Replace the `elsif broadcast_enabled? ... else ...` block with:
```ruby
result.merge!(
  @broadcast_queue.enqueue(
    tx: tx, txid: txid, beef_binary: beef_binary,
    input_outpoints: nil, change_outpoints: nil, fund_ref: nil,
    accept_delayed_broadcast: delayed
  )
)
```

InlineQueue detects `input_outpoints: nil` and skips UTXO state transitions (finalize path has no locked inputs/change).

**`broadcast_and_promote` private method**: Becomes a thin delegate to `@broadcast_queue.enqueue` for any remaining internal callers, or is removed if `promote_no_send` is also refactored.

**`promote_no_send`** (line ~1299): This is called from `send_with` and promotes to `'unproven'` not `'completed'`. Keep this method as-is for now — it has different promotion semantics (unproven + pending index cleanup) that don't fit the queue pattern cleanly. Phase 2 can address this.

**`broadcast_status_for`**: Delegate to `BroadcastQueue.status_for_error(e)`. Keep the private method as a thin wrapper for backward compat.

**`broadcast_enabled?`**: Unchanged — still returns `!@broadcaster.nil?`.

### Task 4: MemoryStore demotion

**Modify:** `gem/bsv-wallet/lib/bsv/wallet_interface/memory_store.rb`

Add to `initialize`:
```ruby
if self.class.warn_in_production? && production_env?
  warn '[bsv-wallet] MemoryStore is intended for testing only. ' \
       'Use PostgresStore for production wallets. ' \
       'Set BSV_MEMORY_STORE_OK=1 to silence this warning.'
end
```

Add class methods:
```ruby
def self.warn_in_production? = @warn_in_production != false
def self.warn_in_production=(val) = (@warn_in_production = val)
```

Add private helper:
```ruby
def production_env?
  env = ENV['RACK_ENV'] || ENV['RAILS_ENV'] || ENV['APP_ENV']
  env && %w[production staging].include?(env) && !ENV['BSV_MEMORY_STORE_OK']
end
```

No impact on test suites (they don't set production env vars).

### Task 5: Specs

**New:** `gem/bsv-wallet/spec/bsv/wallet_interface/broadcast_queue_spec.rb`
- Module raises `NotImplementedError` for `enqueue` and `status`
- `async?` defaults to `false`
- `BroadcastQueue.status_for_error` maps errors correctly

**New:** `gem/bsv-wallet/spec/bsv/wallet_interface/inline_queue_spec.rb`
- With broadcaster, success: promotes state, returns `broadcast_status: 'success'`
- With broadcaster, failure: rolls back, returns `broadcast_error`
- Without broadcaster: promotes immediately, returns BEEF
- Without broadcaster + `accept_delayed_broadcast`: status `'unproven'`
- `async?` returns `false`
- `status(txid)` returns action status from storage
- Finalize path (nil outpoints): only updates action status, no UTXO transitions

**Modify:** `gem/bsv-wallet/spec/bsv/wallet_interface/wallet_client_spec.rb`
- Remove `warn` expectations from `accept_delayed_broadcast` tests (stubs gone)
- Add test: custom `broadcast_queue:` is used when provided
- Add test: auto-created InlineQueue is used by default
- Verify `broadcast_enabled?` still reflects `@broadcaster`

**Modify:** `gem/bsv-wallet/spec/bsv/wallet_interface/memory_store_spec.rb`
- Test production warning emitted when `RACK_ENV=production`
- Test warning suppressed by `BSV_MEMORY_STORE_OK=1`
- Test warning suppressed by `MemoryStore.warn_in_production = false`
- Test no warning in test/development/unset env

**Existing specs** (`broadcast_rollback_spec.rb`, `auto_funding_spec.rb`): Should pass without changes since InlineQueue replicates the same logic. Run full suite to verify.

## Critical files

| File | Action |
|------|--------|
| `gem/bsv-wallet/lib/bsv/wallet_interface/broadcast_queue.rb` | Create |
| `gem/bsv-wallet/lib/bsv/wallet_interface/inline_queue.rb` | Create |
| `gem/bsv-wallet/lib/bsv/wallet_interface.rb` | Modify (autoloads) |
| `gem/bsv-wallet/lib/bsv/wallet_interface/wallet_client.rb` | Modify (constructor, auto-fund path, finalize path) |
| `gem/bsv-wallet/lib/bsv/wallet_interface/memory_store.rb` | Modify (production warning) |

## Verification

```bash
cd /opt/ruby/bsv-ruby-sdk
bundle exec rake spec:wallet        # All wallet specs pass
bundle exec rubocop gem/bsv-wallet/  # Clean
```

Specific checks:
1. Existing `broadcast_rollback_spec.rb` passes unchanged (InlineQueue produces identical results)
2. Existing `accept_delayed_broadcast` specs pass with updated expectations (no warn, same status)
3. `auto_funding_spec.rb` passes unchanged
4. New InlineQueue specs cover all four paths (broadcast+success, broadcast+fail, no-broadcast, no-broadcast+delayed)
5. MemoryStore warning only fires in production-like environments

## Sequencing

```
Task 1 (BroadcastQueue module)  ──→  Task 2 (InlineQueue)  ──→  Task 3 (WalletClient wiring)  ──→  Task 5 (specs)
Task 4 (MemoryStore demotion)   ──  independent, parallel with any task
```
