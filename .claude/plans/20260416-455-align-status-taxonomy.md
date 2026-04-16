# Plan: HLR #455 — Align action status with reference SDK; fail loudly on broadcast misconfiguration

## Context

`bsv-wallet`'s `create_action` and `internalize_action` collapse distinct states into `'completed'`, leading consumers to believe transactions are on-chain when they may not be. This caused phantom-payment bugs in x402-rack (#148, #158) and x402-doom (#196).

The TS reference SDK (wallet-toolbox) distinguishes `'nosend'`, `'unsent'`, `'sending'`, `'unmined'`, `'unproven'`, `'completed'`, `'failed'`. `'completed'` means a merkle proof is on file. Ruby currently uses `'completed'` for "broadcast succeeded" (wrong) and "no broadcaster, nothing on chain" (also wrong, silently).

## Current status-setting sites

| Site | Current | Fix |
|------|---------|-----|
| `auto_fund_and_create` `no_send: true` (wallet_client.rb:814) | `'nosend'` | ✓ keep |
| `auto_fund_and_create` default (wallet_client.rb:834) | `'pending'` (pre-queue) | ✓ keep |
| `finalize_action` (wallet_client.rb:1441-1448) | `'nosend'` or `'pending'` | ✓ keep |
| `InlineQueue#broadcast_and_promote` success (inline_queue.rb:100) | `'completed'` | → `'unproven'` |
| `InlineQueue#broadcast_and_promote` failure (inline_queue.rb:89) | `'failed'` | ✓ keep |
| `InlineQueue#promote_without_broadcast` default (inline_queue.rb:127) | `'completed'` silently | → **raise `WalletError`** (no broadcaster + sync broadcast requested) |
| `InlineQueue#promote_without_broadcast` delayed (inline_queue.rb:127) | `'unproven'` | → `'unproven'` (sync fallback path per #380) |
| `SolidQueueAdapter#process_job` success (solid_queue_adapter.rb:~292) | `'completed'` | → `'unproven'` |
| `SolidQueueAdapter#process_job` failure | `'failed'` | ✓ keep |
| `promote_no_send` success (wallet_client.rb:1416) | `'unproven'` | ✓ keep |
| `internalize_action` via `store_action` (wallet_client.rb:306) | `'completed'` unconditional | → `'completed'` if BEEF has merkle proof for subject tx, else `'unproven'` |
| `store_action` default (wallet_client.rb:1484) | `'completed'` | ✓ keep (tests only use default) |

## Tasks

### Task 1: Add validation in `create_action`

**Modify** `gem/bsv-wallet/lib/bsv/wallet_interface/wallet_client.rb`.

Add a new private method `validate_broadcast_configuration!(args)` called at the top of `create_action` (after `validate_create_action!`):

```ruby
def validate_broadcast_configuration!(args)
  no_send = args.dig(:options, :no_send)
  return if no_send
  return if @broadcaster

  raise WalletError,
        'create_action requires a broadcaster for on-chain broadcast. ' \
        'Pass broadcaster: BSV::Network::ARC.default to WalletClient.new, ' \
        'or options: { no_send: true } to build a transaction without broadcasting.'
end
```

This fails loudly at the call site — not after state has been written to storage.

### Task 2: Fix `InlineQueue` success status

**Modify** `gem/bsv-wallet/lib/bsv/wallet_interface/inline_queue.rb`.

- `broadcast_and_promote` success: change `promote(..., txid)` default from `'completed'` to `'unproven'`. Pass explicit `status: 'unproven'`.
- `promote_without_broadcast`: remove the silent-`'completed'` branch. This method is now reached only via the `accept_delayed_broadcast: true` + no-broadcaster fallback (per #380 design). Status stays `'unproven'`. If somehow called without `accept_delayed_broadcast`, raise `WalletError` — a defensive guard since Task 1 should catch this upstream.
- Update docstrings: `'completed'` → `'unproven'` (on-chain but unproven); `'completed'` only after proof monitoring promotes it (future work).

### Task 3: Fix `SolidQueueAdapter` success status

**Modify** `gem/bsv-wallet-postgres/lib/bsv/wallet_postgres/solid_queue_adapter.rb`.

- `process_job` success path: `promote(..., txid)` should use `status: 'unproven'` instead of `'completed'`.
- Update docstring.

### Task 4: Fix `internalize_action` to check merkle proof

**Modify** `gem/bsv-wallet/lib/bsv/wallet_interface/wallet_client.rb` `internalize_action` (line ~267) and/or `store_proofs_from_beef` / `extract_subject_transaction` / `find_by_subject_txid`.

- Determine whether the BEEF contains a merkle proof (BUMP) for the subject transaction.
- If yes → status = `'completed'`
- If no → status = `'unproven'`
- Pass explicit status to `store_action`

Mirrors TS `storage/methods/internalizeAction.ts:301`:
```typescript
const status: TransactionStatus = provenTx ? 'completed' : 'unproven'
```

### Task 5: Update specs

**Modify** existing specs to reflect the new status values. Files identified:
- `gem/bsv-wallet/spec/bsv/wallet_interface/wallet_client_spec.rb` (2 sites)
- `gem/bsv-wallet/spec/bsv/wallet_interface/wallet_client_auto_fund_spec.rb` (4 sites)
- `gem/bsv-wallet/spec/bsv/wallet_interface/inline_queue_spec.rb` (5 sites)
- `gem/bsv-wallet/spec/bsv/wallet_interface/broadcast_rollback_spec.rb`
- `gem/bsv-wallet/spec/bsv/wallet_interface/auto_funding_spec.rb`
- `gem/bsv-wallet/spec/bsv/wallet_interface/wire/serializer_spec.rb`
- `gem/bsv-wallet-postgres/spec/bsv/wallet_postgres/solid_queue_adapter_spec.rb`

Strategy: global search-and-replace of `'completed'` → `'unproven'` in test expectations where the asserted state is post-broadcast, then review each hit manually to catch exceptions (e.g. `internalize_action` tests with proven BEEFs should stay `'completed'`).

**Add** new specs:
- `create_action` raises `WalletError` when no broadcaster AND `no_send: false` (default)
- `create_action` succeeds with `no_send: true` and no broadcaster → status `'nosend'`
- `create_action` with broadcaster → status `'unproven'` on success
- `internalize_action` with proven BEEF → `'completed'`
- `internalize_action` with unproven BEEF → `'unproven'`
- `SolidQueueAdapter` worker success → status `'unproven'`

### Task 6: Documentation

- **CHANGELOG.md** for `bsv-wallet`: document as breaking change for 0.8.0 with migration notes
- **gem/bsv-wallet/README.md**: update status meanings table
- **docs/gems/wallet.md**: add "Status values" section
- **CLAUDE.md**: no changes needed (general development guidance is already correct)

### Task 7: Downstream coordination

- **bsv-attest**: verify `Attest.publish` callers don't assert `'completed'` — confirmed no assertions, no change needed.
- **bsv-wallet-postgres**: no schema change (status is TEXT). Bump dependency floor to match new wallet version.
- **x402-rack, x402-doom**: will need guidance — `'unproven'` is the new "success" state for fresh broadcasts. Document this in the bsv-wallet 0.8.0 release notes.

## Critical files

| File | Action |
|------|--------|
| `gem/bsv-wallet/lib/bsv/wallet_interface/wallet_client.rb` | Modify — add `validate_broadcast_configuration!`, fix internalize status logic |
| `gem/bsv-wallet/lib/bsv/wallet_interface/inline_queue.rb` | Modify — success status + remove silent fallback |
| `gem/bsv-wallet-postgres/lib/bsv/wallet_postgres/solid_queue_adapter.rb` | Modify — success status |
| `gem/bsv-wallet/CHANGELOG.md` | Update for breaking change |
| `gem/bsv-wallet/README.md` | Update status table |
| `docs/gems/wallet.md` | Add status values section |

## Reference files (read-only)

| File | Why |
|------|-----|
| `wallet-toolbox/src/storage/methods/processAction.ts` | Status state machine reference |
| `wallet-toolbox/src/storage/methods/internalizeAction.ts:301` | Proven vs unproven decision |
| `wallet-toolbox/src/signer/methods/processAction.ts:147-155` | SendWithResult status mapping |

## Verification

```bash
cd /opt/ruby/bsv-ruby-sdk
bundle exec rake spec:wallet           # wallet specs
bundle exec rake spec:wallet_postgres  # postgres specs (SolidQueueAdapter)
bundle exec rake                       # full suite
bundle exec rubocop                    # lint
```

Manual verification:
1. Construct `WalletClient.new(key)` (no broadcaster) and call `create_action` with default options → expect `WalletError`
2. Same + `options: { no_send: true }` → expect success with status `'nosend'`
3. Construct `WalletClient.new(key, broadcaster: ARC.default)` and call `create_action` → expect status `'unproven'` on success
4. Internalize a BEEF with merkle proof → action status `'completed'`
5. Internalize a BEEF without merkle proof → action status `'unproven'`

## Sequencing

```
Task 1 (create_action guard) ──→ Task 5 (specs update)
Task 2 (InlineQueue)          ──→ Task 5
Task 3 (SolidQueueAdapter)    ──→ Task 5
Task 4 (internalize_action)   ──→ Task 5
Task 6 (docs)                 ── independent
Task 7 (downstream floor)     ── last, requires wallet version bump
```

Tasks 1-4 can be done in parallel (touch different code paths). Task 5 must wait for all of them. Tasks 6-7 are independent bookkeeping.
