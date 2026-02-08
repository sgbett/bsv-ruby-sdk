# Testnet Integration Tests for BSV Ruby SDK

## Goal

Add integration tests that exercise the full SDK stack against live BSV testnet — key generation, transaction building, signing, broadcasting, and status queries. Tests are excluded from default `rspec` and CI; run manually with `bundle exec rspec --tag testnet`.

## Infrastructure

- **ARC testnet**: `https://testnet.arc.gorillapool.io` (no API key required)
- **UTXO lookup**: WhatsOnChain testnet API `https://api.whatsonchain.com/v1/bsv/test`
- **Faucet**: `https://witnessonchain.com/faucet/tbsv`
- **Explorer**: `https://test.whatsonchain.com/`

## Files to modify

### 1. `.gitignore` — add `.env`

Prevent accidental commit of testnet credentials.

### 2. `spec/spec_helper.rb` — add tag exclusion + support loading

```ruby
config.filter_run_exclude testnet: true
```

Plus autoload `spec/support/**/*.rb`.

### 3. `.rubocop.yml` — add exclusions for new directories

Add `spec/integration/**/*` to `RSpec/MultipleExpectations` and `RSpec/ExampleLength` exclusions.

## New files

### 4. `spec/support/testnet_wallet.rb`

Test-only helper module (not shipped in the gem) providing:

- `fetch_utxos(address)` — GET WoC `/address/{addr}/unspent`, returns array of `{tx_hash, tx_pos, value}`
- `fetch_raw_tx(txid)` — GET WoC `/tx/{txid}/hex`, returns hex string
- `select_utxos(utxos, min_satoshis)` — greedy selection, raises with faucet URL if insufficient
- `utxo_to_input(utxo, locking_script)` — bridges WoC response to `TransactionInput` with `source_satoshis` and `source_locking_script` attached

Uses only stdlib (`net/http`, `json`, `uri`). No new gems.

### 5. `spec/integration/testnet_spec.rb`

Tagged `:testnet`. Configuration via ENV vars:

| Variable | Required | Default |
|----------|----------|---------|
| `BSV_TESTNET_WIF` | Yes | — |
| `BSV_TESTNET_ARC_URL` | No | `https://testnet.arc.gorillapool.io` |

`before(:context)` loads the key, derives the testnet address, fetches UTXOs, and skips with an informative message if the key is missing or the wallet is empty.

**Test scenarios:**

1. **Wallet setup** — derives a valid `m`/`n`-prefixed testnet address; confirms UTXOs exist
2. **P2PKH transfer** — selects UTXO, builds tx sending 546 sats to self + change, signs, broadcasts via ARC, asserts `BroadcastResponse` with matching txid, queries status
3. **OP_RETURN attestation** — selects UTXO, builds tx with 0-sat OP_RETURN output containing a timestamped string + change, signs, broadcasts, asserts success
4. **Round-trip serialisation** — broadcasts a tx, sleeps 2s for propagation, fetches raw hex from WoC, parses with `Transaction.from_hex`, asserts txid and hex match original

**UTXO contention**: each test group consumes a UTXO. The wallet needs at least 3000 satoshis. Change returns to the same address, so the wallet stays funded across runs. Document this as a prerequisite.

## Implementation order

1. `.gitignore` — add `.env`
2. `spec/support/testnet_wallet.rb` — WoC helper
3. `spec/spec_helper.rb` — tag filter + support loading
4. `spec/integration/testnet_spec.rb` — integration tests
5. `.rubocop.yml` — exclusions for new directories

## Verification

1. `bundle exec rspec` — confirms zero testnet tests run (all excluded by tag)
2. `bundle exec rubocop` — confirms no lint violations
3. Generate a testnet key, fund it, run: `BSV_TESTNET_WIF='cXxx...' bundle exec rspec --tag testnet`
4. Confirm all 5 examples pass and transactions are visible on `https://test.whatsonchain.com/`
