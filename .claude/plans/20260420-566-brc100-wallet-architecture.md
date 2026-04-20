# Plan: BRC-100-Driven Wallet Architecture (#566) — Revised

## Context

`client.rb` is currently 1,712 lines — the god object renamed. Phase 1 (path rename, BRC100 abstract modules, ProtoWallet deletion) is done. The structural scaffolding exists but the actual decomposition hasn't happened. This revised plan delivers the core transformation: distributing the implementation logic across concern modules aligned with BRC-100's six functional areas.

## What Exists Now (on the branch)

- `lib/bsv/wallet/client.rb` — 1,712-line monolith with all 28 BRC-100 methods + 70+ private helpers
- `lib/bsv/wallet/brc100/` — 6 abstract sub-modules + composed Interface (all raise `UnsupportedActionError`)
- `client.rb` includes `BRC100::Interface` then overrides every method with the implementation

## What We're Building

```ruby
class Client
  include BRC100::Interface          # abstract contract (28 stubs)

  include Client::Crypto             # codes 8-16: 9 public + 4 private (~260 lines)
  include Client::TransactionOps     # codes 1-7: 7 public + ~40 private (~900 lines)
  include Client::IdentityOps        # codes 17-22: 6 public + 7 private (~200 lines)
  include Client::NetworkOps         # codes 25-28: 4 public (~40 lines)
  include Client::AuthenticationOps  # codes 23-24: 2 public (~20 lines)

  # Constructor, attr_readers, non-BRC-100 public methods only (~100 lines)
end
```

The BRC100 modules stay abstract (substrates include them safely). The implementation lives in `Client::*` concern modules that only Client includes. `client.rb` drops from 1,712 lines to ~100.

## Method Distribution

Based on the current client.rb method list:

### `client/crypto.rb` — Client::Crypto (~260 lines)
**Public (9):** get_public_key, encrypt, decrypt, create_hmac, verify_hmac, create_signature, verify_signature, reveal_counterparty_key_linkage, reveal_specific_key_linkage
**Private (4):** derive_sym_key, bytes_to_string, string_to_bytes, secure_compare
Each public method has substrate delegation (`return @substrate.X if @substrate`) then local implementation using `@key_deriver`.

### `client/transaction_ops.rb` — Client::TransactionOps (~900 lines)
**Public (7):** create_action, sign_action, abort_action, list_actions, list_outputs, relinquish_output, internalize_action
**Private — validation:** validate_broadcast_configuration!, validate_create_action!, validate_action_inputs!, validate_action_outputs!, validate_list_actions!, validate_list_outputs!, validate_internalize_action!
**Private — build:** parse_input_beef, build_transaction, build_inputs, wire_source, wire_source_from_storage, wire_source_tx_ancestors, build_outputs, shuffle_outputs, needs_signing?, create_signable, apply_spends
**Private — store:** store_action, store_tracked_outputs, build_action_query, build_output_query, strip_action_fields, strip_output_fields, finalize_action
**Private — internalise:** store_proofs_from_beef, extract_subject_transaction, find_by_subject_txid, process_internalize_outputs, internalize_payment, internalize_basket
**Private — auto-fund:** auto_fund_and_create, auto_fund_select, converge_change, load_pool_opts, build_auto_funded_transaction, add_auto_funded_input, add_output_from_spec, store_change_outputs, change_output_entry, auto_fee_estimator, auto_coin_selector, auto_change_generator
**Private — broadcast/state:** release_stale_if_due, release_pending_utxos, rollback_pending_action, broadcast_and_promote, broadcast_send_with, broadcast_single_no_send, promote_no_send, broadcast_status_for

### `client/identity_ops.rb` — Client::IdentityOps (~200 lines)
**Public (6):** acquire_certificate, list_certificates, prove_certificate, relinquish_certificate, discover_by_identity_key, discover_by_attributes
**Private (7):** validate_acquire_certificate!, acquire_via_direct, acquire_via_issuance, auth_fetch_client, execute_http, find_stored_certificate, cert_without_keyring

### `client/network_ops.rb` — Client::NetworkOps (~40 lines)
**Public (4):** get_height, get_header_for_height, get_network, get_version

### `client/authentication_ops.rb` — Client::AuthenticationOps (~20 lines)
**Public (2):** is_authenticated, wait_for_authentication

### `client.rb` — Client (~100 lines)
**Constructor:** initialize (wiring collaborators)
**Attr readers:** key_deriver, storage, network, proof_store, broadcaster, broadcast_queue, substrate
**Non-BRC-100 public:** broadcast_enabled?, sync_utxos, balance, spendable_balance, set_wallet_change_params, utxo_pool
**Private utility:** identity_address, output_exists?, spendable_pool_eligible?
**Constants:** ANCESTOR_DEPTH_CAP, STALE_CHECK_INTERVAL

---

## Implementation Tasks

### Task 1: Extract Client::Crypto (sequential)
Move the 9 crypto public methods + 4 private helpers from client.rb into `lib/bsv/wallet/client/crypto.rb`. Add `include Client::Crypto` to client.rb.
**Files:** create `client/crypto.rb`, modify `client.rb`
**Test:** all specs pass, crypto round-trips work

### Task 2: Extract Client::TransactionOps (sequential, after Task 1)
Move the 7 transaction public methods + all private transaction/auto-fund/broadcast helpers. This is the largest extraction (~900 lines).
**Files:** create `client/transaction_ops.rb`, modify `client.rb`
**Test:** all specs pass, create_action/sign_action/auto-fund work

### Task 3: Extract Client::IdentityOps (sequential, after Task 2)
Move the 6 identity/certificate public methods + 7 private helpers.
**Files:** create `client/identity_ops.rb`, modify `client.rb`
**Test:** all specs pass, certificate operations work

### Task 4: Extract Client::NetworkOps + Client::AuthenticationOps (sequential, after Task 3)
Move the 4 network methods and 2 auth methods. Small enough to do together.
**Files:** create `client/network_ops.rb`, `client/authentication_ops.rb`, modify `client.rb`
**Test:** all specs pass

### Task 5: Verify client.rb is thin
After all extractions, `client.rb` should be ~100 lines: constructor, attr_readers, non-BRC-100 methods, includes, constants. If it's significantly larger, something was missed.
**Acceptance:** `client.rb` under 150 lines, all 1,054 wallet specs pass, gem builds

---

## Critical Files

| File | Action |
|------|--------|
| `lib/bsv/wallet/client.rb` | Shrink from 1,712 to ~100 lines |
| `lib/bsv/wallet/client/crypto.rb` | New: ~260 lines |
| `lib/bsv/wallet/client/transaction_ops.rb` | New: ~900 lines |
| `lib/bsv/wallet/client/identity_ops.rb` | New: ~200 lines |
| `lib/bsv/wallet/client/network_ops.rb` | New: ~40 lines |
| `lib/bsv/wallet/client/authentication_ops.rb` | New: ~20 lines |

## Verification

After each task:
1. `cd gem/bsv-wallet && bundle exec rspec` — all specs pass
2. `bundle exec rubocop gem/bsv-wallet/lib/bsv/wallet/client*` — clean
3. `wc -l gem/bsv-wallet/lib/bsv/wallet/client.rb` — getting smaller

Final:
4. `client.rb` is under 150 lines
5. Every concern module has a clear single responsibility matching a BRC-100 functional area
6. `gem build bsv-wallet.gemspec` — builds
