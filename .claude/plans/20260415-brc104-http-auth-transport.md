# Plan: HLR #436 — BRC-104 HTTP Auth Transport (F8.3)

**HLR**: [#436](https://github.com/sgbett/bsv-ruby-sdk/issues/436)
**Parent**: [#378](https://github.com/sgbett/bsv-ruby-sdk/issues/378)
**Depends on**: #426 (Phase 2 — Peer protocol completion, merged)

## Context

Phase 3 of the wallet/auth epic (#378). The SDK has a mature BRC-31/BRC-103 mutual authentication Peer with session management, certificate exchange, and a clean Transport interface — but no HTTP transport. Without BRC-104, Ruby peers cannot communicate with TS/Go peers over HTTP, and downstream phases (F8.2 substrates, F8.16 certificate issuance) are blocked.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    AuthFetch                          │  Client-side high-level API
│  (peer caching, auto-handshake, 402 payment)         │
├─────────────────────────────────────────────────────┤
│              SimplifiedFetchTransport                 │  Client-side Transport impl
│  (handshake → /.well-known/auth JSON)                │
│  (general  → HTTP + x-bsv-auth-* headers)            │
├──────────────────────┬──────────────────────────────┤
│     AuthPayload      │      AuthHeaders              │  Shared foundation
│  (binary req/resp    │  (header constants,            │
│   serialisation)     │   extraction, filtering)       │
└──────────────────────┴──────────────────────────────┘

                    ↕ HTTP ↕

┌─────────────────────────────────────────────────────┐
│               AuthMiddleware (Rack)                   │  Server-side
│  /.well-known/auth → Peer handshake via bridge        │
│  general requests  → verify → app → sign response     │
├─────────────────────────────────────────────────────┤
│     Peer + SessionManager + AuthPayload               │  Existing + shared
└─────────────────────────────────────────────────────┘
```

### How BRC-104 maps BRC-103 to HTTP

| Message type | HTTP route | Encoding |
|---|---|---|
| `initialRequest` | POST `/.well-known/auth` | JSON body |
| `initialResponse` | POST `/.well-known/auth` | JSON response |
| `certificateRequest` | POST `/.well-known/auth` | JSON body |
| `certificateResponse` | POST `/.well-known/auth` | JSON body |
| `general` | Any HTTP method/path | `x-bsv-auth-*` headers + normal body |

For general messages, the **signature covers a binary serialisation** of the HTTP request/response (matching TS/Go format), but the HTTP body is the actual payload (JSON, etc.), not the binary. Both sides reconstruct the binary for signing/verification.

### Binary payload format (cross-SDK interop)

**Request** (used for signing):
```
[32 bytes]   request nonce
[varint+]    method (UTF-8)
[varint+]    path (UTF-8, or -1 if absent)
[varint+]    search/query (UTF-8, or -1 if absent)
[varint]     header count
  [varint+]  key (UTF-8, lowercase)
  [varint+]  value (UTF-8)
  ...
[varint+]    body bytes (or -1 if absent)
```

**Response** (used for signing):
```
[32 bytes]   request ID (echoed from request)
[varint]     status code
[varint]     header count
  [varint+]  key (UTF-8, lowercase)
  [varint+]  value (UTF-8)
  ...
[varint+]    body bytes (or -1 if absent)
```

Varints use Bitcoin CompactSize (same as `BSV::Transaction::VarInt`). Absent optional fields encode as `0xFFFFFFFFFFFFFFFF` (VarInt MAX_UINT64 = 9 bytes). Headers sorted alphabetically by key.

## Key Design Decisions

### 1. VarInt reuse
Reuse `BSV::Transaction::VarInt` directly. For "absent" fields, encode `VarInt::MAX_UINT64` (0xFFFFFFFFFFFFFFFF). On decode, treat MAX_UINT64 as nil/absent. No changes needed to existing VarInt.

### 2. Net::HTTP (no external deps)
Ruby stdlib `Net::HTTP` for HTTP calls, matching the SDK's zero-external-dependency policy. TS uses browser `fetch`; Go uses `net/http`.

### 3. Server-side: Peer for handshake, direct signing for responses
The Rack middleware uses the Peer via a bridge transport (Queue-based, like Go's `channelTransport`) for the handshake flow. For general messages, the middleware:
1. Reconstructs binary payload from the HTTP request → feeds AuthMessage to Peer for verification
2. Strips auth headers → passes to downstream Rack app
3. Captures app response → serialises response to binary → signs with wallet + session nonces → adds `x-bsv-auth-*` response headers

The Peer's `process_general_message` handles verification + session update + callback firing. Response signing is done by the middleware using the same protocol (`[2, 'auth message signature']`, key_id = `"#{response_nonce} #{client_nonce}"`).

### 4. Bridge transport for server handshake
A small `RequestTransport` (internal to middleware) that uses a Queue for request/response bridging:
- `send(message)` → pushes to response queue
- `on_data(&block)` → stores callback
- `inject(message)` → calls on_data callback (feeds to Peer)
- `wait_for_response` → pops from response queue with timeout

Mutex-protected for concurrent HTTP requests. The Peer's `handle_incoming_message` is synchronous, so inject → process → send all happen in one call stack.

### 5. Thread safety
- AuthFetch: Mutex-protected `@peers` hash (one Peer per base URL)
- AuthMiddleware: Mutex around inject + pop for concurrent requests
- Existing Peer internals already thread-safe (callback_mutex, handshake_queues_mutex)

### 6. Header filtering
Only these headers are included in the signed payload (matching TS SDK):
- `x-bsv-*` (excluding `x-bsv-auth-*`)
- `authorization`
- `content-type` (normalised: no charset/params)

All other headers are passed through but not signed. Headers sorted alphabetically, keys lowercased.

### 7. 402 Payment: include but isolate
The 402 payment flow is complex (Type-42 derivation, wallet.create_action, retry with backoff). Implement as a separate task, isolated in its own method/module within AuthFetch. If wallet.create_action isn't available, raises a clear error rather than silently failing.

## Task Breakdown

### Task 1: Auth HTTP foundation (constants + payload serialiser)

**New files:**
- `lib/bsv/auth/auth_headers.rb` — header name constants, extraction, filtering
- `lib/bsv/auth/auth_payload.rb` — binary serialisation/deserialisation
- `spec/bsv/auth/auth_headers_spec.rb`
- `spec/bsv/auth/auth_payload_spec.rb`

**AuthHeaders module:**
```ruby
module BSV::Auth::AuthHeaders
  VERSION              = 'x-bsv-auth-version'
  IDENTITY_KEY         = 'x-bsv-auth-identity-key'
  NONCE                = 'x-bsv-auth-nonce'
  YOUR_NONCE           = 'x-bsv-auth-your-nonce'
  SIGNATURE            = 'x-bsv-auth-signature'
  REQUEST_ID           = 'x-bsv-auth-request-id'
  MESSAGE_TYPE         = 'x-bsv-auth-message-type'
  REQUESTED_CERTS      = 'x-bsv-auth-requested-certificates'

  # Payment headers (402 flow)
  PAYMENT_VERSION      = 'x-bsv-payment-version'
  PAYMENT_SATOSHIS     = 'x-bsv-payment-satoshis-required'
  PAYMENT_DERIVATION   = 'x-bsv-payment-derivation-prefix'
  PAYMENT              = 'x-bsv-payment'

  ALLOWED_PAYLOAD_HEADERS = /\Ax-bsv-(?!auth-)|authorization|content-type/i
end
```

**AuthPayload module:**
- `serialize_request(request_id:, method:, path:, query:, headers:, body:)` → binary String
- `deserialize_request(data)` → Hash with above keys
- `serialize_response(request_id:, status:, headers:, body:)` → binary String
- `deserialize_response(data)` → Hash with above keys
- Uses `BSV::Transaction::VarInt` for varint encoding
- `ABSENT = VarInt::MAX_UINT64` for optional nil fields
- Headers sorted alphabetically, keys lowercased

**Specs:** Test with known byte sequences. Cross-reference with TS SDK's serialisation output.

### Task 2: SimplifiedFetchTransport

**New files:**
- `lib/bsv/auth/simplified_fetch_transport.rb`
- `spec/bsv/auth/simplified_fetch_transport_spec.rb`

**Class:** `BSV::Auth::SimplifiedFetchTransport`
- Includes `BSV::Auth::Transport`
- Constructor: `initialize(base_url, http_client: nil)` — default Net::HTTP
- `send(message)`:
  - **Non-general** (initialRequest, initialResponse, certRequest, certResponse): POST JSON to `#{base_url}/.well-known/auth`, parse JSON response, call `@on_data_callback`
  - **General**: Deserialise binary payload → HTTP request with `x-bsv-auth-*` headers → receive response → serialise response binary → construct AuthMessage → call `@on_data_callback`
- `on_data(&block)` — stores callback

**Key implementation details:**
- Non-general messages use camelCase keys in JSON for TS/Go interop (the `.well-known/auth` endpoint speaks the cross-SDK wire format)
- General messages append auth headers from the AuthMessage to the HTTP request
- Response auth headers are extracted and used to build the response AuthMessage
- Uses `Net::HTTP.start` with connection reuse per transport instance

**Reuses:** `AuthPayload.deserialize_request`, `AuthPayload.serialize_response`, `AuthHeaders` constants

### Task 3: AuthFetch

**New files:**
- `lib/bsv/auth/auth_fetch.rb`
- `spec/bsv/auth/auth_fetch_spec.rb`

**Class:** `BSV::Auth::AuthFetch`

**Constructor:**
```ruby
def initialize(wallet:, requested_certificates: nil, session_manager: nil)
```

**Public API:**
```ruby
auth_fetch.fetch(url, method: 'GET', headers: {}, body: nil) → AuthResponse
```

**AuthResponse:** Simple value object with `status`, `headers`, `body`, `identity_key` (server's).

**Internal flow:**
1. Parse base URL from full URL
2. Get or create Peer + SimplifiedFetchTransport for base URL (mutex-protected)
3. Generate 32-byte request nonce
4. Filter and sort headers (AuthHeaders.filter)
5. Serialise request via AuthPayload.serialize_request
6. Register response listener via `peer.on_general_message`
7. Send via `peer.to_peer(serialized_payload, nil)` — auto-handshake
8. Wait for response (matched by request nonce in first 32 bytes)
9. Deserialise response via AuthPayload.deserialize_response
10. Return AuthResponse

**Stale session recovery:** On AuthError containing "Session not found", clear cached peer and retry once.

**Thread safety:** `@peers_mutex` protects `@peers` hash.

### Task 4: Server-side auth middleware

**New files:**
- `lib/bsv/auth/auth_middleware.rb`
- `spec/bsv/auth/auth_middleware_spec.rb`

**Class:** `BSV::Auth::AuthMiddleware` (Rack middleware)

**Constructor:**
```ruby
def initialize(app, wallet:, session_manager: nil, certificates_to_request: nil)
```

**Flow:**
```ruby
def call(env)
  if well_known_auth_request?(env)
    handle_auth_endpoint(env)     # Handshake + certs via Peer
  elsif has_auth_headers?(env)
    handle_authenticated_request(env)  # Verify → app → sign
  else
    @app.call(env)                # Pass through (no auth)
  end
end
```

**`handle_auth_endpoint`:**
1. Parse JSON body → build AuthMessage hash
2. Convert camelCase → snake_case keys
3. Inject into Peer via bridge transport
4. Pop response from bridge transport queue
5. Convert snake_case → camelCase keys
6. Return [200, JSON headers, [JSON response]]

**`handle_authenticated_request`:**
1. Extract `x-bsv-auth-*` headers from Rack env
2. Read request body, serialise to binary via AuthPayload
3. Build AuthMessage and inject into Peer for verification
4. If verification fails → 401
5. Strip auth headers from env, reset body IO
6. Call `@app.call(env)` → get [status, headers, body]
7. Serialise response to binary via AuthPayload
8. Generate response nonce, sign binary with wallet
9. Add `x-bsv-auth-*` response headers
10. Return [status, merged_headers, body]

**Bridge transport:** Internal class, Queue-based, mutex-protected.

### Task 5: 402 Payment handling

**Modified file:** `lib/bsv/auth/auth_fetch.rb`
**New file:** `spec/bsv/auth/auth_fetch_payment_spec.rb`

**Integrated into AuthFetch.fetch:**
- After receiving response, check status 402
- Validate payment headers (version "1.0", satoshis > 0, identity key, derivation prefix)
- Generate derivation suffix (nonce)
- Derive payment key: `wallet.get_public_key(protocol_id: [2, '3241645161d8'], key_id: "#{prefix} #{suffix}", counterparty: server_key)`
- Create P2PKH output to derived key
- Create transaction via `wallet.create_action(description:, outputs:)`
- Add `x-bsv-payment` header with JSON `{ derivationPrefix, derivationSuffix, transaction }`
- Retry request (max 3 attempts, 250ms * attempt linear backoff)

**Risk:** `wallet.create_action` may not be implemented in the Ruby SDK's WalletClient. If not available, document as known limitation and raise clear error.

### Task 6: Integration tests

**New file:** `spec/bsv/auth/brc104_integration_spec.rb`

**Test approach:** Use WEBrick or a thin Rack server in-process. AuthFetch client connects to localhost, AuthMiddleware wraps a simple Rack app.

**Scenarios:**
1. Full lifecycle: handshake + authenticated GET request + response
2. Authenticated POST with JSON body
3. Session reuse across multiple requests
4. Certificate exchange during handshake over HTTP
5. Stale session recovery (simulate 401)
6. Multiple clients connecting to same server
7. Pass-through (no auth headers → downstream app)
8. Invalid signature → 401 rejection

## File Summary

| File | Task | New/Modified |
|------|------|-------------|
| `lib/bsv/auth.rb` | 1 | Modified (add autoloads) |
| `lib/bsv/auth/auth_headers.rb` | 1 | New |
| `lib/bsv/auth/auth_payload.rb` | 1 | New |
| `lib/bsv/auth/simplified_fetch_transport.rb` | 2 | New |
| `lib/bsv/auth/auth_fetch.rb` | 3 | New |
| `lib/bsv/auth/auth_middleware.rb` | 4 | New |
| `spec/bsv/auth/auth_headers_spec.rb` | 1 | New |
| `spec/bsv/auth/auth_payload_spec.rb` | 1 | New |
| `spec/bsv/auth/simplified_fetch_transport_spec.rb` | 2 | New |
| `spec/bsv/auth/auth_fetch_spec.rb` | 3 | New |
| `spec/bsv/auth/auth_middleware_spec.rb` | 4 | New |
| `spec/bsv/auth/auth_fetch_payment_spec.rb` | 5 | New |
| `spec/bsv/auth/brc104_integration_spec.rb` | 6 | New |

## Task Sequence

```
Task 1 (foundation) → Task 2 (transport) → Task 3 (client) ──→ Task 5 (402)
                   ↘                     ↘                  ↗
                    Task 4 (server) ─────→ Task 6 (integration)
```

Tasks 3 and 4 are independent of each other (both depend on 1 and 2 for shared modules, but 4 doesn't use SimplifiedFetchTransport — it uses its own bridge transport). Could be parallelised but sequential is safer.

Recommended sequence: **1 → 2 → 3 → 4 → 5 → 6**

## Risks

1. **Wire format interop**: Binary serialisation must match TS/Go byte-for-byte. Mitigation: test vectors extracted from TS SDK tests.
2. **402 payment**: Requires `wallet.create_action` which may not exist. Mitigation: isolate in Task 5, document limitation if wallet method unavailable.
3. **Rack body handling**: Rack request bodies are IO objects that can only be read once. Middleware must `rewind` after reading for auth verification.
4. **camelCase ↔ snake_case**: The `.well-known/auth` JSON endpoint uses camelCase (cross-SDK wire format), but Ruby internals use snake_case. Need careful key conversion at the boundary.
5. **Connection management**: Net::HTTP persistent connections need careful lifecycle management. Use `Net::HTTP.start` block for automatic cleanup.

## Verification

```bash
cd gem/bsv-sdk

# Unit tests per task
bundle exec rspec spec/bsv/auth/auth_headers_spec.rb
bundle exec rspec spec/bsv/auth/auth_payload_spec.rb
bundle exec rspec spec/bsv/auth/simplified_fetch_transport_spec.rb
bundle exec rspec spec/bsv/auth/auth_fetch_spec.rb
bundle exec rspec spec/bsv/auth/auth_middleware_spec.rb
bundle exec rspec spec/bsv/auth/brc104_integration_spec.rb

# Full suite
bundle exec rspec

# Lint
bundle exec rubocop
```
