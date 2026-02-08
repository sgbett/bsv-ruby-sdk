# BSV Ruby SDK — Network Layer

## Goal

Implement `BSV::Network` — the fourth top-level module in the SDK dependency chain (Primitives → Script → Transaction → Network). This enables broadcasting signed transactions to the BSV network via the ARC API, completing the end-to-end flow needed for attestation (#7).

## Key Technical Decisions

- **`BSV::Network` as a top-level module.** Broadcasting is an imperative concern (sending data) distinct from the declarative layers (Primitives, Script, Transaction). Own module, own namespace.
- **Raise on failure, return response on success.** Idiomatic Ruby. `BroadcastError < StandardError` for failures (following `Base58::ChecksumError` pattern). `BroadcastResponse` value object for successes.
- **Duck-typed broadcaster contract.** No abstract base class — any object responding to `#broadcast(tx)` satisfies the contract. Documented in comments.
- **Injectable HTTP client for testability.** `ARC.new(url, http_client: mock)` — specs never hit the network. Default uses `Net::HTTP` from stdlib.
- **`application/octet-stream` content type.** Binary bytes via `tx.to_binary`, matching the Go SDK approach (half the payload size vs hex).
- **MVP scope.** Submit tx, query status, response/error classes. Deferred: batch broadcast, callbacks, policy endpoint, fee quotes.

## File Structure

```
lib/bsv/
  network.rb                          # autoload hub
  network/
    broadcast_error.rb                # BroadcastError exception class
    broadcast_response.rb             # BroadcastResponse value object
    arc.rb                            # ARC broadcaster implementation

spec/bsv/network/
    broadcast_error_spec.rb
    broadcast_response_spec.rb
    arc_spec.rb
```

## Build Order (4 steps)

### 1. `BroadcastError` — custom exception

**File:** `lib/bsv/network/broadcast_error.rb`

- `class BroadcastError < StandardError`
- `attr_reader :status_code, :txid`
- `initialize(message, status_code: nil, txid: nil)`

Carries HTTP status code and txid as structured data alongside the error message.

### 2. `BroadcastResponse` — success value object

**File:** `lib/bsv/network/broadcast_response.rb`

- `attr_reader :txid, :tx_status, :message, :extra_info, :block_hash, :block_height, :timestamp, :competing_txs`
- `initialize(attrs = {})` — hash constructor for flexibility
- `success?` → always `true` (failures raise instead)
- `mined?` → `tx_status == 'MINED'`

ARC JSON key mapping: `txStatus` → `tx_status`, `blockHash` → `block_hash`, `blockHeight` → `block_height`, `extraInfo` → `extra_info`, `competingTxs` → `competing_txs`, `title` → `message`.

### 3. `ARC` — broadcaster implementation

**File:** `lib/bsv/network/arc.rb`

Requires: `net/http`, `json`, `uri` (all stdlib).

Constructor:
- `initialize(url, api_key: nil, http_client: nil)`
- Strips trailing slash from URL

Public methods:
- `broadcast(tx)` — `POST {url}/tx`, body: `tx.to_binary`, content-type: `application/octet-stream`. Returns `BroadcastResponse`, raises `BroadcastError` on failure.
- `status(txid)` — `GET {url}/tx/{txid}`. Returns `BroadcastResponse`, raises `BroadcastError` on failure.

Private methods:
- `apply_auth_header(request)` — sets `Authorization: Bearer <key>` if `api_key` present
- `execute(uri, request)` — delegates to injectable `@http_client` or falls back to `Net::HTTP.start` with SSL auto-detection
- `handle_broadcast_response(response)` — parses JSON, raises on non-2xx or rejected status, builds `BroadcastResponse` on success
- `rejected_status?(tx_status)` — checks for `REJECTED` and `DOUBLE_SPEND_ATTEMPTED`
- `parse_json(raw)` — graceful JSON parsing, wraps non-JSON in a hash
- `build_response(body)` — maps ARC JSON to `BroadcastResponse`

**Error handling:**
1. Non-2xx HTTP → raise `BroadcastError` with `detail` or `title` from body
2. HTTP 200 but `txStatus` is `REJECTED` or `DOUBLE_SPEND_ATTEMPTED` → raise `BroadcastError` (matches TS SDK pattern)
3. Non-JSON response body → gracefully wrap raw text

**Test strategy (injectable mock):**

Specs use a mock HTTP client that stores the last request and returns a configurable response. Tests cover:
- Successful broadcast → returns `BroadcastResponse` with correct fields
- HTTP error (e.g. 400, 465) → raises `BroadcastError` with status code
- ARC rejection (200 + `REJECTED` status) → raises `BroadcastError`
- Double spend (200 + `DOUBLE_SPEND_ATTEMPTED`) → raises `BroadcastError`
- Request headers: `Content-Type`, `Authorization` presence/absence
- Request body: binary transaction bytes
- Status query: correct GET URL, returns `BroadcastResponse`
- URL trailing slash normalisation
- Non-JSON response handling

### 4. Wire up autoloads + RuboCop config

- `lib/bsv/network.rb` — autoload hub for `BroadcastError`, `BroadcastResponse`, `ARC`
- `lib/bsv-sdk.rb` — add `autoload :Network, 'bsv/network'`
- `.rubocop.yml` — add `lib/bsv/network/**/*` and `spec/bsv/network/**/*` to metric exclusions

## ARC API Reference

### `POST /v1/tx` — submit transaction
- Content-Type: `application/octet-stream` (raw binary)
- Auth: `Authorization: Bearer <key>` (optional)
- Response: `{ txid, txStatus, status, title, extraInfo, blockHash, blockHeight, timestamp, competingTxs }`
- Success: HTTP 200, `txStatus` is one of: `SEEN_ON_NETWORK`, `MINED`, etc.
- Errors: HTTP 400–475, or HTTP 200 with `txStatus: REJECTED/DOUBLE_SPEND_ATTEMPTED`

### `GET /v1/tx/{txid}` — query status
- Same response shape as submit

## Commit Sequence

1. `feat(network): add BroadcastError exception class`
2. `feat(network): add BroadcastResponse value object`
3. `feat(network): add ARC broadcaster with injectable HTTP client`
4. `chore(network): wire up autoloads and extend RuboCop exclusions`

## Deferred Work

- Batch broadcast (`POST /v1/txs`)
- ARC callback headers (`X-CallbackUrl`, `X-CallbackToken`, `X-WaitFor`, etc.)
- Policy endpoint (`GET /v1/policy`) and fee quote integration
- Convenience method on Transaction: `tx.broadcast(broadcaster)`
- Additional broadcaster implementations (WhatsOnChain, etc.)
- Retry logic / timeout configuration

## Verification

```bash
bundle exec rspec spec/bsv/network/   # all network specs pass
bundle exec rubocop                    # no lint violations
bundle exec rake                       # full suite green
```
