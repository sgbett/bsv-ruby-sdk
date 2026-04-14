# Plan: HLR #426 — Peer Protocol Completion (F8.4, F8.5)

**HLR**: [#426](https://github.com/sgbett/bsv-ruby-sdk/issues/426)
**Parent**: [#378](https://github.com/sgbett/bsv-ruby-sdk/issues/378)
**Depends on**: #419 (Phase 1 — Certificate infrastructure, PR #425)
**Findings**: F8.4 (certificate exchange messages), F8.5 (high-level session API)

## API Design: Converge on TS SDK

The TS SDK's Peer has a transport-driven design:
- Transport is required
- `handleIncomingMessage` is private — messages arrive via `transport.onData`
- Public API: `toPeer`, `getAuthenticatedSession`, `requestCertificates`, `sendCertificateResponse`, callback registration

Ruby's current Peer is the opposite — manual message building, optional transport, `handle_incoming_message` is public. This phase converges on the TS model:

- **Transport required** in constructor (raise `ArgumentError` if nil)
- **`handle_incoming_message` becomes private** — only called via `transport.on_data`
- **Public API matches TS**: `to_peer`, `get_authenticated_session`, `request_certificates`, `send_certificate_response`, callbacks
- **Existing manual methods** (`create_initial_request`, `create_general_message`) become private internals
- **Existing specs migrated** to use a `PairedTransport` test helper

This is a breaking change to the Peer API, but the SDK is pre-1.0 and the current manual API has no external consumers. The migration is straightforward — replace direct hash-passing with transport-mediated communication.

### PairedTransport test helper

Connects two peers bidirectionally for in-process testing:

```ruby
class PairedTransport
  include BSV::Auth::Transport

  attr_accessor :partner

  def initialize
    @on_data_callback = nil
  end

  def send(message)
    @partner.deliver(message)
  end

  def on_data(&block)
    @on_data_callback = block
  end

  def deliver(message)
    @on_data_callback&.call(message)
  end
end
```

When Peer A calls `to_peer`:
1. A builds request → `transport_a.send(request)`
2. → `transport_b.deliver(request)` → `peer_b.handle_incoming_message(request)`
3. → B builds response → `transport_b.send(response)`
4. → `transport_a.deliver(response)` → `peer_a.handle_incoming_message(response)`

All synchronous, same thread. The `Queue` in `initiate_handshake` is already populated by the time `pop` is called.

## Sync/Async Strategy

### The problem

The TS SDK is fully async (Promises). Key patterns that need Ruby equivalents:

1. **`getAuthenticatedSession`** — sends `initialRequest` via transport, `await`s a Promise resolved when `processInitialResponse` fires via `on_data` callback.
2. **Certificate validation blocking** — `processGeneralMessage` creates a 30-second Promise waiting for certificates to arrive via `processCertificateResponse`.
3. **`initiateHandshake`** — sends request, returns a Promise resolved when the response arrives.

### Solution: Thread + Queue

`get_authenticated_session` sends `initialRequest` via transport, then blocks on `Queue#pop` with timeout. `process_initial_response` pushes to the queue when authentication completes.

**Why this works for both sync and async transports:**

With `PairedTransport` (sync, in-process):
```
Peer A: initiate_handshake
  → transport_a.send(request)
    → transport_b.deliver(request)
      → peer_b.handle_incoming_message(request)
        → peer_b builds response → transport_b.send(response)
          → transport_a.deliver(response)
            → peer_a.handle_incoming_message(response)
              → peer_a.process_initial_response pushes to queue
  → queue.pop returns immediately (data already pushed on same call stack)
```

With async transport (HTTP, WebSocket):
```
Thread A: initiate_handshake → transport.send(request) → queue.pop blocks
Thread B: transport.on_data fires → handle_incoming_message → process_initial_response → queue.push
Thread A: queue.pop unblocks → returns session nonce
```

### Certificate validation blocking: Go approach (reject immediately)

The TS SDK blocks `processGeneralMessage` for up to 30 seconds waiting for certificates. The Go SDK rejects immediately with `ErrNotAuthenticated`.

**We follow Go**: reject the general message immediately if certificates are required but not validated. Reasons:
- Avoids complex `ConditionVariable` + timeout in message processing
- Simpler, more predictable
- Clear error message guides the caller to validate certificates first
- Application can use `on_certificates_received` callback for async handling

## Architecture

```
BSV::Auth::Peer (converged on TS model)
  │── Public API (transport-driven)
  │     │── to_peer(payload, identity_key)
  │     │── get_authenticated_session(identity_key)
  │     │── request_certificates(certs_to_request, identity_key)
  │     └── send_certificate_response(peer_identity_key, certificates)
  │
  │── Callbacks
  │     │── on_general_message / off_general_message
  │     │── on_certificates_received / off_certificates_received
  │     └── on_certificate_request / off_certificate_request
  │
  │── Readers
  │     │── identity_key
  │     │── authenticated?(identifier)
  │     └── last_interacted_peer
  │
  │── Private internals (message building + processing)
  │     │── handle_incoming_message (dispatch → 5 types)
  │     │── initiate_handshake
  │     │── process_initial_request / process_initial_response
  │     │── process_certificate_request / process_certificate_response
  │     │── process_general_message
  │     │── build_general_message / build_certificate_request / build_certificate_response
  │     └── helpers (key_id_for, b64_decode, fetch!, fire_callbacks)
  │
  └── Internal state
        │── @callbacks { type → { id → Proc } }
        │── @callback_id_counter
        │── @last_interacted_peer
        │── @handshake_queues { session_nonce → Queue }
        └── @callback_mutex (Mutex)

BSV::Auth.validate_certificates(wallet, message, requested_certificates)
BSV::Auth.get_verifiable_certificates(wallet, requested_certificates, verifier_key)
```

## Task Breakdown

### Task 1: `validate_certificates` utility

**New file:** `gem/bsv-sdk/lib/bsv/auth/validate_certificates.rb`
**Spec:** `gem/bsv-sdk/spec/bsv/auth/validate_certificates_spec.rb`

Module method `BSV::Auth.validate_certificates(wallet, message, requested_certificates = nil)`:

1. Raise `AuthError` if `message[:certificates]` nil or empty
2. For each certificate:
   a. Verify `cert.subject == message[:identity_key]` — raise if mismatch
   b. Construct `VerifiableCertificate` from hash (handle both Hash and VerifiableCertificate inputs)
   c. Verify certificate signature via `cert.verify` — raise if invalid
   d. If `requested_certificates` provided: check certifier in requested set, type in requested set
   e. Decrypt fields via `cert.decrypt_fields(wallet)` — raise if fails

**Dependencies:** None (uses Phase 1 certificate classes).

### Task 2: `get_verifiable_certificates` utility

**New file:** `gem/bsv-sdk/lib/bsv/auth/get_verifiable_certificates.rb`
**Spec:** `gem/bsv-sdk/spec/bsv/auth/get_verifiable_certificates_spec.rb`

Module method `BSV::Auth.get_verifiable_certificates(wallet, requested_certificates, verifier_identity_key)`:

1. Return `[]` unless wallet responds to `list_certificates` and `prove_certificate`
2. Call `wallet.list_certificates(...)` for matching certs
3. For each, call `wallet.prove_certificate(...)` to get verifier keyring
4. Construct `VerifiableCertificate` from certificate data + keyring
5. Return array

Guard with `respond_to?` — `ProtoWallet` doesn't support these methods.

**Dependencies:** None (but see #424 re: prove_certificate bug).

### Task 3: PairedTransport test helper + migrate existing specs

**New file:** `gem/bsv-sdk/spec/support/paired_transport.rb`
**Modified:** `gem/bsv-sdk/spec/bsv/auth/peer_spec.rb`

Create `PairedTransport` helper (see above). Migrate existing peer specs from manual hash-passing to transport-mediated communication. All existing test scenarios must continue to pass.

This is a prerequisite for Task 6 (which makes `handle_incoming_message` private) but can be done early since the current Peer still accepts a transport.

**Dependencies:** None.

### Task 4: Callback registration system + `@last_interacted_peer`

**Modified:** `gem/bsv-sdk/lib/bsv/auth/peer.rb`

Add to `initialize`:
```ruby
@callbacks = { general_message: {}, certificates_received: {}, certificate_request: {} }
@callback_id_counter = 0
@callback_mutex = Mutex.new
@last_interacted_peer = nil
@auto_persist_last_session = true  # new kwarg
```

Public methods:
- `on_general_message(&block) → Integer` / `off_general_message(id)`
- `on_certificates_received(&block) → Integer` / `off_certificates_received(id)`
- `on_certificate_request(&block) → Integer` / `off_certificate_request(id)`
- `attr_reader :last_interacted_peer`

Private helper: `fire_callbacks(type, *args)` — iterates and calls each block.

All access through `@callback_mutex` for thread safety.

Update `@last_interacted_peer` tracking points:
- `process_initial_request`: set if nil
- `process_initial_response`: always set
- `process_general_message`: always set

Wire callbacks into existing message processors:
- `process_general_message`: fire `:general_message` callbacks with `(peer_identity_key, payload)`

**Dependencies:** None (purely additive).

### Task 5: Certificate exchange message processing (F8.4 core)

**Modified:** `gem/bsv-sdk/lib/bsv/auth/peer.rb`
**Extended spec:** `gem/bsv-sdk/spec/bsv/auth/peer_spec.rb`

**5a.** Wire `MSG_CERT_REQUEST` and `MSG_CERT_RESPONSE` into `handle_incoming_message` dispatch.

**5b.** `process_certificate_request(message)` (private):
- Verify nonce, look up session, verify signature over `JSON.generate(requested_certificates).encode('UTF-8').bytes`
- Fire `on_certificate_request` callbacks if registered, else auto-fetch via `BSV::Auth.get_verifiable_certificates` and respond
- Key ID: `"#{nonce} #{session.session_nonce}"`

**5c.** `process_certificate_response(message)` (private):
- Verify nonce, look up session, verify signature over `JSON.generate(certificates).encode('UTF-8').bytes`
- Validate certificates via `BSV::Auth.validate_certificates`
- Mark `session.certificates_validated = true`
- Fire `on_certificates_received` callbacks
- Key ID: `"#{nonce} #{session.session_nonce}"`

**5d.** Update `process_initial_request` — include certificates in response via callback/auto-fetch when peer's `requested_certificates` has certifiers.

**5e.** Update `process_initial_response` — validate certificates if present in response, handle peer's `requested_certificates` (fire callbacks or auto-respond).

**Signature protocol** (same for all BRC-103 messages):
- Protocol: `[2, 'auth message signature']`
- Key ID: `"#{nonce} #{session_nonce}"`
- Counterparty: peer identity key
- Data: UTF-8 bytes of `JSON.generate(payload_data)`

**Dependencies:** Tasks 1, 2, 4.

### Task 6: High-level session API (F8.5 core) + API convergence

**Modified:** `gem/bsv-sdk/lib/bsv/auth/peer.rb`

This task delivers the high-level API and makes the API change: transport required, manual methods private.

**6a.** Make transport required in `initialize`:
```ruby
def initialize(wallet:, transport:, session_manager: nil, certificates_to_request: nil,
               auto_persist_last_session: true, handshake_timeout: 30)
  raise ArgumentError, 'transport is required' if transport.nil?
  # ...
end
```

**6b.** `get_authenticated_session(identity_key = nil)`:
1. Resolve `identity_key` from `@last_interacted_peer` if nil
2. Look up existing session — return if authenticated
3. Call `initiate_handshake(identity_key)` — blocks until response
4. Return authenticated session

**6c.** `initiate_handshake(identity_key = nil)` (private):
1. Create nonce, add pending session
2. Create `Queue.new`, store in `@handshake_queues[session_nonce]`
3. Build `initialRequest` message
4. Send via `@transport.send(message)` — wrapped in begin/rescue to clean up queue on failure
5. Block on `queue.pop` with `Timeout.timeout(@handshake_timeout)`
6. On timeout: clean up queue, raise `AuthError`
7. Return session nonce

Queue push in `process_initial_response`, after authentication:
```ruby
queue = @handshake_queues.delete(session.session_nonce)
queue&.push(:ready)
```

**6d.** `to_peer(payload, identity_key = nil)`:
1. Resolve identity_key
2. Get authenticated session
3. Raise `AuthError` if certificates required but not validated (Go approach)
4. Build and send general message via transport
5. Update `@last_interacted_peer`

**6e.** `request_certificates(certificates_to_request, identity_key = nil)`:
1. Get authenticated session
2. Build and sign `certificateRequest` message
3. Send via transport

**6f.** `send_certificate_response(peer_identity_key, certificates)`:
1. Get authenticated session
2. Build and sign `certificateResponse` message
3. Send via transport

**6g.** Make private: `handle_incoming_message`, `create_initial_request`, `create_general_message`, all `process_*` methods, all `build_*` methods.

**Dependencies:** Tasks 3, 4, 5.

### Task 7: Autoload and module wiring

**Modified:** `gem/bsv-sdk/lib/bsv/auth.rb`

Add requires/autoloads for new utility files (`validate_certificates.rb`, `get_verifiable_certificates.rb`).

**Dependencies:** Tasks 1, 2.

### Task 8: Integration tests

**New spec files:**
- `gem/bsv-sdk/spec/bsv/auth/validate_certificates_spec.rb`
- `gem/bsv-sdk/spec/bsv/auth/peer_integration_spec.rb`

**Key test scenarios:**

Certificate exchange:
1. Full lifecycle: issue cert → handshake with cert request → auto-respond with certs → validate → decrypt
2. Dynamic cert request post-handshake: `request_certificates` → callback fires → `send_certificate_response` → validated
3. Tampered certificate rejected
4. Wrong certifier rejected
5. Subject mismatch rejected

High-level API:
1. `to_peer` auto-handshakes and sends, callback fires on receiver
2. `get_authenticated_session` returns existing session on second call
3. `to_peer` raises when certificates required but not validated
4. `request_certificates` → `on_certificate_request` fires on other peer
5. `@last_interacted_peer` tracked and used as default

Edge cases:
1. Handshake timeout when transport doesn't deliver response
2. Transport send failure doesn't leave orphaned queue entries
3. Multiple concurrent sessions with different peers

**Dependencies:** All previous tasks.

## Implementation Sequence

```
Task 1 (validate_certificates) ─────┐
                                      │
Task 2 (get_verifiable_certs) ───────┤
                                      ├──→ Task 5 (cert msg processing) ──┐
Task 3 (PairedTransport + migrate) ──┤                                    │
                                      │                                    │
Task 4 (callbacks + last_peer) ──────┘                                    │
                                                                           │
                                    Task 7 (autoload) ── after 1, 2       │
                                                                           │
                                    Task 6 (high-level API + converge) ───┤
                                                                           │
                                    Task 8 (integration tests) ───────────┘
```

**Parallel group 1:** Tasks 1, 2, 3, 4 (no cross-dependencies)
**Sequential after group 1:** Task 5 (depends on 1, 2, 4), Task 7 (depends on 1, 2)
**Sequential after Task 5:** Task 6 (depends on 3, 5)
**Final:** Task 8 (depends on all)

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| JSON serialisation mismatch (Ruby `JSON.generate` vs TS `JSON.stringify`) | Signatures don't cross-verify | Add cross-SDK test vectors; verify key ordering matches |
| Thread safety for shared state | Race conditions in transport mode | `@callback_mutex` protects callbacks, queues, counter, last_interacted_peer |
| Queue deadlock if `transport.send` raises before response | `initiate_handshake` hangs until timeout | Wrap `send` in begin/rescue that cleans up queue on failure |
| #424 (prove_certificate protocol mismatch) | Auto-fetch path produces incompatible keyrings | Guard with `respond_to?`; callback path unaffected; document limitation |
| `ProtoWallet` doesn't support `list_certificates`/`prove_certificate` | Auto-fetch returns empty array | Guard with `respond_to?`; tests use mocks for auto-fetch path |
| Breaking change to Peer API | Existing code using manual API breaks | Pre-1.0 SDK; no external consumers; migration path is PairedTransport |

## Deliberate Deviations from TS SDK

| Behaviour | TS SDK | Ruby (this plan) | Rationale |
|-----------|--------|-------------------|-----------|
| Certificate validation blocking | 30-second Promise wait in `processGeneralMessage` | Immediate rejection (Go approach) | Avoids `ConditionVariable` complexity; clearer error handling |
| `originator` parameter | Threaded through all wallet calls | Not implemented | Ruby SDK doesn't have originator concept yet; deferred |
| Callback method naming | `listenForGeneralMessages` / `stopListeningForGeneralMessages` | `on_general_message` / `off_general_message` | Ruby idiom (event emitter pattern) |

## Status

| Task | Status |
|------|--------|
| Task 1: validate_certificates | Not started |
| Task 2: get_verifiable_certificates | Not started |
| Task 3: PairedTransport + spec migration | Not started |
| Task 4: Callbacks + last_interacted_peer | Not started |
| Task 5: Certificate exchange processing | Not started |
| Task 6: High-level API + API convergence | Not started |
| Task 7: Autoload wiring | Not started |
| Task 8: Integration tests | Not started |
