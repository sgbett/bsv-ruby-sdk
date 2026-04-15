# Plan: HLR #445 — Phase 4 Wallet Integration (F8.2/F8.11/F8.12/F8.16)

**HLR**: [#445](https://github.com/sgbett/bsv-ruby-sdk/issues/445)
**Parent**: [#378](https://github.com/sgbett/bsv-ruby-sdk/issues/378)
**Depends on**: #436 (Phase 3 — BRC-104 HTTP auth transport, merged)

## Context

Phase 3 delivered BRC-104 HTTP auth (`AuthFetch`, `SimplifiedFetchTransport`, `AuthMiddleware`). Phase 4 connects the wallet layer to this infrastructure and fills three remaining cross-SDK gaps: HTTP substrates for remote wallet communication (F8.2), include flags for list queries (F8.12), and authenticated certificate issuance (F8.16). F8.11 (wire format translator) is foundational infrastructure needed by the substrates.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    WalletClient                          │
│  substrate: nil → local storage (existing)               │
│  substrate: HTTPWalletJSON → JSON-over-HTTP              │
│  substrate: WalletWireTransceiver(HTTPWalletWire) → wire │
├─────────────────────────────────────────────────────────┤
│                    Substrates                            │
│  ┌─────────────────────┐  ┌──────────────────────────┐  │
│  │   HTTPWalletJSON     │  │  WalletWireTransceiver   │  │
│  │  (implements         │  │  (wraps WalletWire →     │  │
│  │   Interface)         │  │   implements Interface)  │  │
│  │  POST /methodName    │  ├──────────────────────────┤  │
│  │  JSON body           │  │    HTTPWalletWire        │  │
│  │  uses WireFormat     │  │  (implements WalletWire) │  │
│  │  for key conversion  │  │  POST /callName          │  │
│  └─────────────────────┘  │  binary body              │  │
│                            │  uses Wire::Serializer    │  │
│                            └──────────────────────────┘  │
├─────────────────────────────────────────────────────────┤
│  BSV::WireFormat (in bsv-sdk)                            │
│  deep_snake_to_camel / deep_camel_to_snake               │
│  Shared by substrates + AuthMiddleware + FetchTransport  │
└─────────────────────────────────────────────────────────┘
```

## Task Breakdown

### Task 1: WireFormat module (F8.11)

**Problem:** camelCase↔snake_case conversion is duplicated inline in `AuthMiddleware` (shallow, lines 281–302) and `SimplifiedFetchTransport` (lookup table + fallback, lines 240–269). HTTPWalletJSON will need deep conversion. Need a shared module.

**Location:** `gem/bsv-sdk/lib/bsv/wire_format.rb` as `BSV::WireFormat`

Lives in bsv-sdk because both existing consumers (AuthMiddleware, SimplifiedFetchTransport) are in bsv-sdk. The wallet gem depends on bsv-sdk and can reuse it.

**Public API:**
- `BSV::WireFormat.to_wire(hash)` — deep snake_case → camelCase key conversion
- `BSV::WireFormat.from_wire(hash)` — deep camelCase → snake_case key conversion
- `BSV::WireFormat.snake_to_camel(str)` — single string conversion
- `BSV::WireFormat.camel_to_snake(str)` — single string conversion

**Implementation:**
- Merge the lookup table from `SimplifiedFetchTransport::SNAKE_TO_CAMEL` with BRC-100 method parameter names (extracted from `Wire::Serializer` write methods)
- Generic fallback for unknown keys (regex-based, same as existing)
- Deep conversion recurses into nested Hashes and Arrays
- Values are NOT converted — only Hash keys
- Edge case: user-data hashes (e.g., certificate `fields`) have arbitrary keys that should NOT be converted. Handle by convention: the caller wraps user-data before passing, or we document that to_wire/from_wire converts ALL keys and callers must handle exceptions

**Refactoring:**
- `auth_middleware.rb`: replace private `snake_case_keys`, `camel_case_keys`, `camel_to_snake`, `snake_to_camel` with `BSV::WireFormat` calls
- `simplified_fetch_transport.rb`: replace `SNAKE_TO_CAMEL`, `CAMEL_TO_SNAKE`, private conversion methods with `BSV::WireFormat` calls

**Files:**
| File | Action |
|------|--------|
| `gem/bsv-sdk/lib/bsv/wire_format.rb` | New |
| `gem/bsv-sdk/lib/bsv-sdk.rb` | Modified (add autoload) |
| `gem/bsv-sdk/lib/bsv/auth/auth_middleware.rb` | Modified (use WireFormat) |
| `gem/bsv-sdk/lib/bsv/auth/simplified_fetch_transport.rb` | Modified (use WireFormat) |
| `gem/bsv-sdk/spec/bsv/wire_format_spec.rb` | New |

---

### Task 2: Include flags for list_actions/list_outputs (F8.12)

**Problem:** `build_action_query` and `build_output_query` discard include flags. All storage adapters return complete hashes.

**Strategy:** Post-fetch field stripping in `WalletClient`, not in storage adapters. This keeps the storage interface clean and works identically across MemoryStore, FileStore, and PostgresStore. The storage layer continues to return full data; WalletClient strips fields based on caller's include flags.

**Default behaviour:** Flags default to `false` (matching TS SDK). When a flag is absent or false, the corresponding field is deleted from each result hash. When explicitly `true`, the field is preserved.

**list_actions flags:**
- `include_labels` → strip `:labels` when false
- `include_inputs` → strip `:inputs` when false (currently not stored — no-op for now, but future-proof)
- `include_input_source_locking_scripts` → strip nested `:source_locking_script` within inputs
- `include_input_unlocking_scripts` → strip nested `:unlocking_script` within inputs
- `include_outputs` → strip `:outputs` when false (currently not stored — no-op for now)
- `include_output_locking_scripts` → strip nested `:locking_script` within outputs

**list_outputs flags:**
- `include_tags` → strip `:tags` when false
- `include_labels` → strip `:labels` when false
- `include_custom_instructions` → strip `:custom_instructions` when false

**Implementation:** Two private methods in WalletClient:
- `strip_action_fields(actions, args)` — returns new array with fields removed
- `strip_output_fields(outputs, args)` — returns new array with fields removed

Uses `Hash#reject` / `Hash#select` (Ruby 2.7 compatible, avoids `Hash#except`).

**Files:**
| File | Action |
|------|--------|
| `gem/bsv-wallet/lib/bsv/wallet_interface/wallet_client.rb` | Modified (list_actions, list_outputs, new private strip methods) |
| `gem/bsv-wallet/spec/bsv/wallet_interface/wallet_client_spec.rb` | Modified (add include flag specs) |

---

### Task 3: BRC-100 HTTP substrates (F8.2)

Three new classes + module wiring + WalletClient integration.

#### Task 3a: Substrates module + HTTPWalletJSON

**Class:** `BSV::Wallet::Substrates::HTTPWalletJSON`
- Includes `BSV::Wallet::Interface`
- Constructor: `initialize(base_url, originator: nil, http_client: nil)`
- Each of 28 Interface methods delegates to private `call(method_name, args)`
- `call` does: `BSV::WireFormat.to_wire(args)` → `POST #{base_url}/#{camel_method}` with JSON body → parse response → `BSV::WireFormat.from_wire(response)`
- Uses `Net::HTTP` (no AuthFetch — matching TS SDK)
- Origin header sent for originator identification
- Error handling: non-2xx raises `WalletError` with decoded error body

**Method name mapping:** Derive camelCase method names from `CALL_CODES.keys` via `BSV::WireFormat.snake_to_camel`. Store as a class constant `METHOD_NAMES`.

#### Task 3b: HTTPWalletWire

**Class:** `BSV::Wallet::Substrates::HTTPWalletWire`
- Constructor: `initialize(base_url, originator: nil, http_client: nil)`
- Single method: `transmit_to_wallet(message)` → returns byte array
- Parses call code from `message[0]`, maps via `Wire::Serializer::METHODS_BY_CODE`
- POSTs binary payload to `#{base_url}/#{camel_call_name}` with `Content-Type: application/octet-stream`
- Returns response body as byte array

#### Task 3c: WalletWireTransceiver

**Class:** `BSV::Wallet::Substrates::WalletWireTransceiver`
- Includes `BSV::Wallet::Interface`
- Constructor: `initialize(wire, originator: nil)`
- Each Interface method: serialize via `Wire::Serializer.serialize_request` → `@wire.transmit_to_wallet(frame.bytes)` → deserialize via `Wire::Serializer.deserialize_response`
- Single private `transmit(method_name, args, originator)` handles the pattern

#### Task 3d: WalletClient substrate integration

Add `substrate:` keyword to `WalletClient#initialize`. When set, Interface methods delegate to the substrate:

```ruby
def create_action(args, originator: nil)
  return @substrate.create_action(args, originator: originator) if @substrate
  # existing local logic...
end
```

Pattern repeated for all 28 methods. Local storage, key derivation, etc. remain for the non-substrate path.

**Files:**
| File | Action |
|------|--------|
| `gem/bsv-wallet/lib/bsv/wallet_interface/substrates.rb` | New (autoloads) |
| `gem/bsv-wallet/lib/bsv/wallet_interface/substrates/http_wallet_json.rb` | New |
| `gem/bsv-wallet/lib/bsv/wallet_interface/substrates/http_wallet_wire.rb` | New |
| `gem/bsv-wallet/lib/bsv/wallet_interface/substrates/wallet_wire_transceiver.rb` | New |
| `gem/bsv-wallet/lib/bsv/wallet_interface.rb` | Modified (add Substrates autoload) |
| `gem/bsv-wallet/lib/bsv/wallet_interface/wallet_client.rb` | Modified (substrate: param) |
| `gem/bsv-wallet/spec/bsv/wallet_interface/substrates/http_wallet_json_spec.rb` | New |
| `gem/bsv-wallet/spec/bsv/wallet_interface/substrates/http_wallet_wire_spec.rb` | New |
| `gem/bsv-wallet/spec/bsv/wallet_interface/substrates/wallet_wire_transceiver_spec.rb` | New |

---

### Task 4: AuthFetch certificate issuance (F8.16)

**Problem:** `acquire_via_issuance` (wallet_client.rb:1582–1620) uses plain `Net::HTTP::Post`. Should use `AuthFetch` for mutual authentication.

**Approach:** Lazy-create an `AuthFetch` instance on first issuance call. `WalletClient` passes `self` as the wallet to `AuthFetch.new(wallet: self)`. This is safe because AuthFetch only calls crypto methods (`get_public_key`, `create_signature`) which are provided by `ProtoWallet` (the superclass) and don't depend on storage or the issuance flow.

```ruby
def acquire_via_issuance(args)
  response = auth_fetch_client.fetch(
    args[:certifier_url],
    method: 'POST',
    headers: { 'content-type' => 'application/json' },
    body: JSON.generate({
      type: args[:type],
      subject: @key_deriver.identity_key,
      certifier: args[:certifier],
      fields: args[:fields]
    })
  )

  raise WalletError, "Certificate issuance failed: HTTP #{response.status}" unless (200..299).cover?(response.status)

  body = JSON.parse(response.body)
  # ... existing cert construction + CertificateSignature.verify! ...
end

def auth_fetch_client
  @auth_fetch ||= BSV::Auth::AuthFetch.new(wallet: self)
end
```

The existing `execute_http` helper and `@http_client` injection remain for other uses. The `@http_client` parameter is not removed for backward compatibility.

**Files:**
| File | Action |
|------|--------|
| `gem/bsv-wallet/lib/bsv/wallet_interface/wallet_client.rb` | Modified (acquire_via_issuance, new auth_fetch_client helper) |
| `gem/bsv-wallet/spec/bsv/wallet_interface/wallet_client_spec.rb` | Modified (AuthFetch issuance specs) |

## Task Dependencies

```
Task 1 (WireFormat) ───→ Task 3a (HTTPWalletJSON)
                    ───→ AuthMiddleware/FetchTransport refactoring
                                                        ↘
Task 2 (include flags)   ← independent                  Task 3d (WalletClient substrate:)
                                                        ↗
Task 3b (HTTPWalletWire) ← independent ──→ Task 3c (Transceiver)

Task 4 (AuthFetch issuance) ← independent
```

**Recommended sequence:** 1 → 2 → 3b → 3c → 3a → 3d → 4

Tasks 1, 2, and 4 are independent of each other — could be parallelised. Task 3a needs Task 1. Tasks 3b/3c are independent of Task 1 but must precede 3d.

## Key Design Decisions

1. **WireFormat in bsv-sdk, not bsv-wallet.** Both existing consumers (AuthMiddleware, SimplifiedFetchTransport) live in bsv-sdk. Placing it there avoids import direction issues.

2. **Post-fetch stripping for include flags, not storage-level filtering.** Keeps the storage interface unchanged. All three adapters continue to return full data. WalletClient applies the cosmetic stripping. This is simpler and less risky than modifying three separate storage implementations plus the PostgresStore in a different gem.

3. **Substrates use plain HTTP, not AuthFetch.** Matches TS SDK. Substrates are transport layers for wallet-to-wallet communication. AuthFetch is for authenticated HTTP to arbitrary servers (certifiers, APIs).

4. **Lazy AuthFetch for issuance.** Created on first use, not at construction time. Avoids overhead when certificates aren't used. `self` as the wallet is safe because only crypto methods are called.

5. **No auto-detection.** Unlike the TS SDK's WalletClient which tries multiple substrates, the Ruby version accepts an explicit `substrate:` parameter. Auto-detection is a browser concern; Ruby is server-side.

## Verification

```bash
# Task 1
cd gem/bsv-sdk && bundle exec rspec spec/bsv/wire_format_spec.rb
cd gem/bsv-sdk && bundle exec rspec spec/bsv/auth/auth_middleware_spec.rb
cd gem/bsv-sdk && bundle exec rspec spec/bsv/auth/simplified_fetch_transport_spec.rb

# Task 2
cd gem/bsv-wallet && bundle exec rspec spec/bsv/wallet_interface/wallet_client_spec.rb

# Task 3
cd gem/bsv-wallet && bundle exec rspec spec/bsv/wallet_interface/substrates/

# Task 4
cd gem/bsv-wallet && bundle exec rspec spec/bsv/wallet_interface/wallet_client_spec.rb

# Full suite + lint
bundle exec rake
bundle exec rubocop
```
