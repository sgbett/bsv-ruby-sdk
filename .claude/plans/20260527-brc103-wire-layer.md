# BRC-103 Wire Layer — HLR #761

## Context

Issue #761. Implements the BRC-103 wire layer so the Ruby SDK can drive any BRC-100 wallet (and so `bsv-wallet` can later expose its `Engine` over HTTP via #223).

Splits into four pieces with a strict dependency order:

```
WERR_* errors ─┐
               ├─► Per-call serializers ─► WalletWireTransceiver ─► HTTP substrates
Branded-type   │
validators ────┘
Frame codec ───┘
```

References (mirror semantically, not syntactically):
- Go: `/opt/ruby/bsv-reference-sdks/go-sdk/wallet/serializer/` (28 files, 7,278 LOC) and `wallet/substrates/`
- Py: `/opt/ruby/bsv-reference-sdks/py-sdk/bsv/wallet/serializer/` and `bsv/wallet/substrates/`
- TS: `ts-sdk/src/wallet/substrates/`, `src/wallet/validationHelpers.ts` (~1215 LOC)

Existing Ruby surface to extend (not replace):
- `lib/bsv/wallet/interface/brc100.rb` — 28-method abstract module with full YARD docs
- `lib/bsv/wallet/proto_wallet.rb` — implements the 9 crypto methods
- `lib/bsv/wallet/proto_wallet/validators.rb` — protocol_id / key_id validation only
- `lib/bsv/wallet/errors.rb` — base error classes (review and extend, don't replace)
- `lib/bsv/wire_format.rb` — snake↔camel mapper (reuse for JSON substrate)

---

## File Structure

```
lib/bsv/wallet/
├── errors.rb                          # MODIFIED — add WERR_* hierarchy + codes
├── wire/                              # NEW namespace
│   ├── frame.rb                       # request_frame + result_frame codec
│   ├── calls.rb                       # Call enum (1..28 → method symbol)
│   ├── validation.rb                  # branded-type predicates (HexString, …)
│   └── reader_writer.rb               # binary read/write helpers (varint, str_with_len, …)
├── wire.rb                            # autoload entry for wire/ namespace
├── serializer/                        # NEW — 28 per-call codec modules + shared common
│   ├── common.rb                      # shared field encoders (outpoint, beef, satoshis, …)
│   ├── certificate.rb                 # cert serialise/deserialise (reused by 4 calls)
│   ├── create_action_args.rb
│   ├── create_action_result.rb
│   ├── sign_action_args.rb
│   ├── sign_action_result.rb
│   ├── abort_action.rb
│   ├── list_actions.rb
│   ├── internalize_action.rb
│   ├── list_outputs.rb
│   ├── relinquish_output.rb
│   ├── get_public_key.rb
│   ├── reveal_counterparty_key_linkage.rb
│   ├── reveal_specific_key_linkage.rb
│   ├── encrypt.rb
│   ├── decrypt.rb
│   ├── create_hmac.rb
│   ├── verify_hmac.rb
│   ├── create_signature.rb
│   ├── verify_signature.rb
│   ├── acquire_certificate.rb
│   ├── list_certificates.rb
│   ├── prove_certificate.rb
│   ├── relinquish_certificate.rb
│   ├── discover_by_identity_key.rb
│   ├── discover_by_attributes.rb
│   ├── discover_certificates_result.rb # shared by 2 calls
│   ├── status.rb                       # is_authenticated + wait_for_authentication
│   ├── get_height.rb
│   ├── get_header_for_height.rb
│   ├── get_network.rb
│   └── get_version.rb
├── serializer.rb                      # autoload entry; module dispatch by Call
├── wallet_wire.rb                     # NEW — abstract transport: transmit(bytes) → bytes
├── wallet_wire_transceiver.rb         # NEW — implements Interface::BRC100 over any WalletWire
├── wallet_wire_processor.rb           # NEW — server-side dispatcher over Interface::BRC100
└── substrates/
    ├── http_wallet_json.rb            # NEW — JSON-RPC HTTP wallet (camelCase wire)
    └── http_wallet_wire.rb            # NEW — BRC-103 binary HTTP wallet

spec/bsv/wallet/
├── wire/
│   ├── frame_spec.rb
│   ├── validation_spec.rb
│   └── reader_writer_spec.rb
├── serializer/
│   ├── common_spec.rb
│   ├── certificate_spec.rb
│   └── <one spec per call>.rb         # 28 round-trip specs
├── wallet_wire_transceiver_spec.rb
├── wallet_wire_processor_spec.rb
├── substrates/
│   ├── http_wallet_json_spec.rb
│   └── http_wallet_wire_spec.rb
└── conformance/brc103/
    ├── vectors_spec.rb                # cross-SDK round-trip vectors
    └── fixtures/                       # binary vectors captured from TS SDK
        └── <call_name>_<scenario>.bin
```

---

## Phase 1 — Foundation (no dependencies; ships first)

### 1a. `WERR_*` error hierarchy

Edit `lib/bsv/wallet/errors.rb` to add codes and named subclasses. Keep existing classes; add the BRC-100 standard hierarchy.

```ruby
module BSV
  module Wallet
    class WalletError < StandardError
      attr_reader :code, :wallet_stack
      def initialize(message = nil, code: 1, stack: '')
        super(message)
        @code = code
        @wallet_stack = stack
      end

      # For wire framing — never leaks Ruby's internal backtrace
      def to_wire = { code: code, message: message, stack: wallet_stack }
    end

    # BRC-100 standard codes (port of TS walletErrors enum)
    class WERR_INVALID_OPERATION    < WalletError; def initialize(m=nil)=super(m,code:1);end;end
    class WERR_UNSUPPORTED_ACTION   < WalletError; def initialize(m=nil)=super(m,code:2);end;end
    class WERR_INVALID_HMAC         < WalletError; def initialize(m=nil)=super(m,code:3);end;end
    class WERR_INVALID_SIGNATURE    < WalletError; def initialize(m=nil)=super(m,code:4);end;end
    class WERR_INSUFFICIENT_FUNDS   < WalletError; def initialize(m=nil)=super(m,code:5);end;end
    class WERR_INVALID_PARAMETER    < WalletError; def initialize(m=nil)=super(m,code:6);end;end
    class WERR_REVIEW_ACTIONS       < WalletError; def initialize(m=nil)=super(m,code:7);end;end

    # Rehydrate from a wire result frame
    def self.error_from_wire(code, message, stack = '')
      klass = {
        1 => WERR_INVALID_OPERATION, 2 => WERR_UNSUPPORTED_ACTION,
        3 => WERR_INVALID_HMAC,      4 => WERR_INVALID_SIGNATURE,
        5 => WERR_INSUFFICIENT_FUNDS,6 => WERR_INVALID_PARAMETER,
        7 => WERR_REVIEW_ACTIONS
      }.fetch(code, WalletError)
      klass.new(message).tap { |e| e.instance_variable_set(:@wallet_stack, stack) }
    end
  end
end
```

`bsv-wallet` will subsequently catch its domain errors at the `WireProcessor` boundary and map them to these — that mapping lives in bsv-wallet#223, not here.

### 1b. Frame codec — `lib/bsv/wallet/wire/frame.rb`

Two pure-function pairs (port of `go-sdk/wallet/serializer/frame.go`):

**Request frame (client → wallet):**
```
[1 byte: call]
[1 byte: originator_len]
[originator_len bytes: originator UTF-8]
[remaining bytes: params]
```

**Result frame (wallet → client):**
```
[1 byte: error_code]   — 0x00 = success
If error:
  [VarInt: message_len][message_len bytes: UTF-8]
  [VarInt: stack_len  ][stack_len   bytes: UTF-8]
Else:
  [remaining bytes: result payload]
```

API:
```ruby
BSV::Wallet::Wire::Frame.write_request(call:, originator:, params:) → String  (binary)
BSV::Wallet::Wire::Frame.read_request(bytes)  → { call:, originator:, params: }
BSV::Wallet::Wire::Frame.write_result(payload:)  → String
BSV::Wallet::Wire::Frame.write_error(error:)     → String
BSV::Wallet::Wire::Frame.read_result(bytes)      → String         # raises WalletError on err byte
```

### 1c. Call enum — `lib/bsv/wallet/wire/calls.rb`

```ruby
module BSV::Wallet::Wire::Calls
  CREATE_ACTION                    = 1
  SIGN_ACTION                      = 2
  ABORT_ACTION                     = 3
  LIST_ACTIONS                     = 4
  INTERNALIZE_ACTION               = 5
  LIST_OUTPUTS                     = 6
  RELINQUISH_OUTPUT                = 7
  GET_PUBLIC_KEY                   = 8
  REVEAL_COUNTERPARTY_KEY_LINKAGE  = 9
  REVEAL_SPECIFIC_KEY_LINKAGE      = 10
  ENCRYPT                          = 11
  DECRYPT                          = 12
  CREATE_HMAC                      = 13
  VERIFY_HMAC                      = 14
  CREATE_SIGNATURE                 = 15
  VERIFY_SIGNATURE                 = 16
  ACQUIRE_CERTIFICATE              = 17
  LIST_CERTIFICATES                = 18
  PROVE_CERTIFICATE                = 19
  RELINQUISH_CERTIFICATE           = 20
  DISCOVER_BY_IDENTITY_KEY         = 21
  DISCOVER_BY_ATTRIBUTES           = 22
  IS_AUTHENTICATED                 = 23
  WAIT_FOR_AUTHENTICATION          = 24
  GET_HEIGHT                       = 25
  GET_HEADER_FOR_HEIGHT            = 26
  GET_NETWORK                      = 27
  GET_VERSION                      = 28

  CALL_TO_METHOD = {
    CREATE_ACTION => :create_action,
    # … full table
  }.freeze

  METHOD_TO_CALL = CALL_TO_METHOD.invert.freeze
end
```

### 1d. Branded-type validators — `lib/bsv/wallet/wire/validation.rb`

Port of TS `validationHelpers.ts`. One predicate per BRC-100 branded type. Each raises `WERR_INVALID_PARAMETER` with the parameter name + reason; never returns a boolean.

```ruby
module BSV::Wallet::Wire::Validation
  module_function

  def hex_string!(name, value, length: nil) ... end           # /\A[0-9a-fA-F]*\z/
  def base64_string!(name, value) ... end
  def outpoint_string!(name, value) ... end                   # /\A[0-9a-fA-F]{64}\.\d+\z/
  def pub_key_hex!(name, value) ... end                       # 66 chars, 02/03 prefix
  def description_5_to_50!(name, value) ... end
  def label_5_to_50!(name, value) ... end
  def basket_5_to_300!(name, value) ... end
  def originator_domain!(name, value) ... end                 # <= 250 bytes
  def satoshi_value!(name, value) ... end                     # 0..21_000_000 * 10^8
  def positive_integer_or_zero!(name, value) ... end
  def protocol_string_5_to_400!(name, value) ... end
  def key_id_string_5_to_800!(name, value) ... end
  def wallet_counterparty!(name, value) ... end               # 'self' | 'anyone' | pub_key_hex
  def wallet_protocol!(name, value) ... end                   # [security_level, name]
  def acquisition_protocol!(name, value) ... end              # 'direct' | 'issuance'
  # … etc
end
```

Reuse `BSV::Wallet::ProtoWallet::Validators` where it already covers a type; move shared logic into `Wire::Validation` and delegate from `ProtoWallet::Validators` to keep one source of truth.

### 1e. Reader/writer helpers — `lib/bsv/wallet/wire/reader_writer.rb`

Thin wrappers over `BSV::Primitives::Utils::Reader/Writer` (or `StringIO`) for the BRC-103 idioms:
- `write_varint(n)`, `read_varint`
- `write_str_with_varint_len(s)`, `read_str_with_varint_len`
- `write_optional_bool(v)` (0 = nil, 1 = false, 2 = true) — Go uses this for `Option<bool>` fields
- `write_satoshis(n)` (8-byte LE uint64), `read_satoshis`
- `write_outpoint(txid_hex, vout)` (32-byte wtxid + 4-byte LE vout), `read_outpoint`

**Deliverable for Phase 1:** errors, frame, calls, validation, reader_writer all merged. Foundation specs all green.

---

## Phase 2 — Per-call serializers

28 modules under `lib/bsv/wallet/serializer/`. Each module exposes one or both of:

```ruby
module BSV::Wallet::Serializer::CreateActionArgs
  module_function
  def serialize(args)   → String (binary)
  def deserialize(bytes) → Hash
end
```

For calls with separate args and result (most), two files: `<call>_args.rb` and `<call>_result.rb`. For simple calls (encrypt, decrypt, get_network …), one file containing `Args` + `Result` modules.

**Shared helpers** live in `serializer/common.rb` (BEEF byte arrays, output specs, input specs) and `serializer/certificate.rb` (the on-wire certificate format reused by `acquire_certificate`, `list_certificates`, `prove_certificate`, `discover_*_result`).

### Sequencing within Phase 2

Land in **complexity order** so the simpler ones validate the foundation before the heavyweights:

1. **Trivial** (no args / minimal args) — `get_network`, `get_version`, `get_height`, `is_authenticated`, `wait_for_authentication`, `get_header_for_height`. ~50 LOC each.
2. **Crypto** — `encrypt`, `decrypt`, `create_hmac`, `verify_hmac`, `create_signature`, `verify_signature`, `get_public_key`, `reveal_counterparty_key_linkage`, `reveal_specific_key_linkage`. ~75–100 LOC each.
3. **Outputs / certs** — `list_outputs`, `relinquish_output`, `acquire_certificate`, `list_certificates`, `prove_certificate`, `relinquish_certificate`, `discover_by_identity_key`, `discover_by_attributes`. ~100–150 LOC each.
4. **Heavyweights** — `create_action_args`, `create_action_result`, `sign_action_args`, `sign_action_result`, `internalize_action`, `list_actions`. ~150–250 LOC each.

Each serializer ships with:
- Round-trip spec (`serialize → deserialize → equal`)
- Reference vector spec (binary fixture captured from Go SDK; check that `deserialize(fixture) == expected_hash`)

### Dispatch table — `lib/bsv/wallet/serializer.rb`

```ruby
module BSV::Wallet::Serializer
  SERIALIZE_ARGS = {
    Wire::Calls::CREATE_ACTION    => CreateActionArgs.method(:serialize),
    Wire::Calls::SIGN_ACTION      => SignActionArgs.method(:serialize),
    # …
  }.freeze

  DESERIALIZE_RESULT = {
    Wire::Calls::CREATE_ACTION    => CreateActionResult.method(:deserialize),
    # …
  }.freeze

  # Server-side inverse: DESERIALIZE_ARGS, SERIALIZE_RESULT
end
```

**Deliverable for Phase 2:** all 28 serializers green against round-trip + Go-generated vectors.

---

## Phase 3 — `WalletWire` + `WalletWireTransceiver`

### `lib/bsv/wallet/wallet_wire.rb` — abstract transport

```ruby
module BSV::Wallet
  module WalletWire
    # @param message [String] binary request frame
    # @return [String] binary result frame
    def transmit_to_wallet(message)
      raise NotImplementedError
    end
  end
end
```

### `lib/bsv/wallet/wallet_wire_transceiver.rb` — client

Implements every method of `Interface::BRC100` by:
1. Validate args via `Wire::Validation`.
2. Serialize args via `Serializer::DISPATCH[call]`.
3. Frame as request via `Wire::Frame.write_request(call:, originator:, params:)`.
4. Send via `@wire.transmit_to_wallet(frame)`.
5. Unframe result via `Wire::Frame.read_result(reply)` (raises `WERR_*` if error byte non-zero).
6. Deserialize payload via `Serializer::DESERIALIZE_RESULT[call]`.
7. Return the hash matching the `Interface::BRC100` doc'd return shape.

```ruby
class BSV::Wallet::WalletWireTransceiver
  include BSV::Wallet::Interface::BRC100

  def initialize(wire)
    @wire = wire
  end

  def create_action(**args)
    Wire::Validation.create_action_args!(args)
    params = Serializer::CreateActionArgs.serialize(args)
    reply  = @wire.transmit_to_wallet(
      Wire::Frame.write_request(call: Wire::Calls::CREATE_ACTION,
                                 originator: args[:originator].to_s,
                                 params: params)
    )
    payload = Wire::Frame.read_result(reply)
    Serializer::CreateActionResult.deserialize(payload)
  end

  # … 27 more identical-shape methods (generate via macro? Keep explicit for grep/IDE.)
end
```

Use a small DSL to remove the boilerplate:

```ruby
class_eval do
  Wire::Calls::CALL_TO_METHOD.each do |call_byte, method_name|
    define_method(method_name) do |**args|
      _dispatch(call_byte, method_name, args)
    end
  end
end
```

Decision: keep explicit definitions where validation is non-trivial; use the metaprogrammed path for the trivial getters.

### `lib/bsv/wallet/wallet_wire_processor.rb` — server

Generic dispatcher. Takes any `Interface::BRC100` implementation. Frames in, frames out. Lives in bsv-sdk so it's usable by anyone with a BRC-100 impl — bsv-wallet#223 will wrap it in a Rack app.

```ruby
class BSV::Wallet::WalletWireProcessor
  def initialize(wallet)  # any object implementing Interface::BRC100
    @wallet = wallet
  end

  # @param request_bytes [String] binary request frame
  # @return [String] binary result frame
  def transmit_to_wallet(request_bytes)
    req = Wire::Frame.read_request(request_bytes)
    method_name = Wire::Calls::CALL_TO_METHOD.fetch(req[:call])
    args = Serializer::DESERIALIZE_ARGS[req[:call]].call(req[:params])
    args[:originator] = req[:originator] unless req[:originator].empty?
    result = @wallet.public_send(method_name, **args)
    payload = Serializer::SERIALIZE_RESULT[req[:call]].call(result)
    Wire::Frame.write_result(payload: payload)
  rescue BSV::Wallet::WalletError => e
    Wire::Frame.write_error(error: e)
  rescue StandardError => e
    Wire::Frame.write_error(error: BSV::Wallet::WERR_INVALID_OPERATION.new(e.message))
  end
end
```

**Deliverable for Phase 3:** transceiver and processor exercise round-trip on a `ProtoWallet` (where the 9 implemented crypto methods round-trip end-to-end; the other 19 raise `NotImplementedError` → mapped to `WERR_UNSUPPORTED_ACTION`).

---

## Phase 4 — HTTP substrates

### `lib/bsv/wallet/substrates/http_wallet_wire.rb` — binary substrate

```ruby
class BSV::Wallet::Substrates::HTTPWalletWire
  include BSV::Wallet::WalletWire

  def initialize(base_url:, http_client: Net::HTTP, headers: {})
    @uri = URI("#{base_url}/wallet")
    @http_client = http_client
    @headers = headers
  end

  def transmit_to_wallet(message)
    req = Net::HTTP::Post.new(@uri, @headers.merge('Content-Type' => 'application/octet-stream'))
    req.body = message
    res = @http_client.start(@uri.hostname, @uri.port, use_ssl: @uri.scheme == 'https') { |h| h.request(req) }
    raise BSV::Wallet::WERR_INVALID_OPERATION.new("HTTP #{res.code}: #{res.body}") unless res.is_a?(Net::HTTPSuccess)
    res.body.b
  end
end
```

Wraps in `WalletWireTransceiver` to expose `Interface::BRC100`:

```ruby
wallet = BSV::Wallet::WalletWireTransceiver.new(
  BSV::Wallet::Substrates::HTTPWalletWire.new(base_url: 'https://wallet.example')
)
wallet.create_action(description: 'hi', outputs: […], originator: 'app.example')
```

### `lib/bsv/wallet/substrates/http_wallet_json.rb` — JSON substrate

Different shape — does **not** use the binary frame codec. Calls `POST /v1/wallet/:method_in_camelCase` with JSON body, parses JSON response. Reuses `BSV::WireFormat` for snake↔camel.

```ruby
class BSV::Wallet::Substrates::HTTPWalletJSON
  include BSV::Wallet::Interface::BRC100

  def initialize(base_url:, http_client: Net::HTTP, headers: {})
    @base = URI(base_url)
    @http_client = http_client
    @headers = headers
  end

  Wire::Calls::CALL_TO_METHOD.each_value do |method_name|
    define_method(method_name) do |**args|
      _post_json(method_name, args)
    end
  end

  private

  def _post_json(method_name, args)
    wire_name = BSV::WireFormat.snake_to_camel(method_name.to_s)
    uri = URI.join(@base.to_s, "/v1/wallet/#{wire_name}")
    body = BSV::WireFormat.snake_to_camel(args).to_json
    req = Net::HTTP::Post.new(uri, @headers.merge('Content-Type' => 'application/json'))
    req.body = body
    res = @http_client.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') { |h| h.request(req) }
    parsed = JSON.parse(res.body)
    if res.is_a?(Net::HTTPSuccess)
      BSV::WireFormat.camel_to_snake(parsed).transform_keys(&:to_sym)
    else
      raise BSV::Wallet.error_from_wire(parsed['code'] || 1, parsed['message'] || res.body, parsed['stack'].to_s)
    end
  end
end
```

**Deliverable for Phase 4:** both substrates pass smoke specs against a `WebMock`-stubbed wallet. Integration suite gated on `BSV_WALLET_URL` env var.

---

## Phase 5 — Conformance vectors

Capture binary fixtures from the Go SDK once and check them in. The Go SDK's `wallet/serializer/*_test.go` files emit deterministic vectors — write a small Go program (or use the existing test data in `wallet/substrates/testdata/`) to dump (request_bytes, expected_args_hash) tuples to `spec/conformance/brc103/fixtures/`.

Spec shape:

```ruby
# spec/bsv/wallet/conformance/brc103/vectors_spec.rb
Dir.glob('spec/bsv/wallet/conformance/brc103/fixtures/*.json').each do |fixture_path|
  fixture = JSON.parse(File.read(fixture_path), symbolize_names: true)
  describe fixture[:name] do
    it 'deserialises the captured request frame to the expected args' do
      frame = [fixture[:request_hex]].pack('H*')
      request = BSV::Wallet::Wire::Frame.read_request(frame)
      args = BSV::Wallet::Serializer::DESERIALIZE_ARGS[request[:call]].call(request[:params])
      expect(BSV::WireFormat.snake_to_camel(args)).to eq(fixture[:expected_args])
    end

    it 'serialises the expected args to the captured request frame' do
      args = BSV::WireFormat.camel_to_snake(fixture[:expected_args]).transform_keys(&:to_sym)
      params = BSV::Wallet::Serializer::SERIALIZE_ARGS[fixture[:call]].call(args)
      frame = BSV::Wallet::Wire::Frame.write_request(call: fixture[:call], originator: fixture[:originator], params: params)
      expect(frame.unpack1('H*')).to eq(fixture[:request_hex])
    end
  end
end
```

One fixture per call (28 minimum); add scenario variants where the Go tests do.

---

## Existing Code to Reuse

- `BSV::WireFormat` (`lib/bsv/wire_format.rb`) — snake↔camel mapper. Confirmed acronym handling (`txid` stays `txid`).
- `BSV::Primitives::Utils::Reader/Writer` — already used by BEEF and MerklePath; mirrors `go-sdk/util/Reader/Writer`. Reuse rather than reinventing in `wire/reader_writer.rb` — that file becomes a thin façade with the BRC-103-specific idioms only.
- `BSV::Primitives::Hex.validate_wtxid!` / `validate_dtxid_hex!` — already enforces wire-byte-order vs display-byte-order. Use inside outpoint serialisation.
- `BSV::Wallet::ProtoWallet` — implements the 9 crypto methods of `Interface::BRC100`. Acts as the integration-test wallet for Phase 3 (transceiver round-trips against an in-process ProtoWallet via a fake `WalletWire` that loops bytes back through `WalletWireProcessor`).
- `BSV::Wallet::ProtoWallet::Validators` — partial validator coverage. Migrate its logic into `Wire::Validation` and have the existing module delegate, preserving the public API.

---

## Wiring

- `lib/bsv-sdk.rb` — add autoloads for `BSV::Wallet::Wire`, `BSV::Wallet::Serializer`, `BSV::Wallet::WalletWire`, `BSV::Wallet::WalletWireTransceiver`, `BSV::Wallet::WalletWireProcessor`, `BSV::Wallet::Substrates`.
- `lib/bsv/wallet.rb` — add the same autoloads inside the `Wallet` module so `BSV::Wallet::*` resolves without going through the umbrella file.
- `bsv-sdk.gemspec` — no new runtime dependencies (`net/http`, `json`, `stringio` are stdlib). Add `webmock` to dev deps for substrate specs if not already there.

---

## RuboCop

`Metrics/ClassLength` will likely fire on the heavyweight serializers (`create_action_args.rb`, `internalize_action.rb`). Acceptable to bump per-file in `.rubocop.yml` under `serializer/` — Go and Py both keep these as single large files because the wire format is one indivisible spec. Don't fragment them artificially.

`Metrics/MethodLength` and `Metrics/AbcSize` — same calculus; allow generously inside `Serializer::*` namespaces and `Wire::Validation`.

---

## Commit Strategy

One commit per phase, with sub-commits per logical chunk:

- **Phase 1 (foundation):** one commit each for errors / frame / calls / validation / reader_writer.
- **Phase 2 (serializers):** one commit per complexity tier (4 commits — trivial, crypto, outputs+certs, heavyweights). Each tier ships with its round-trip + vector specs.
- **Phase 3:** one commit for `WalletWire` + `WalletWireTransceiver`, one for `WalletWireProcessor`, one for the loopback integration spec.
- **Phase 4:** one commit per substrate.
- **Phase 5:** one commit for the conformance fixture harness, then commits as fixtures are added.

Each commit message uses conventional commits scoped to `wallet`: `feat(wallet): add BRC-103 frame codec`, etc.

---

## Verification

End-state checklist (mirrors HLR #761 acceptance criteria):

- [ ] 28 per-call serializer modules under `lib/bsv/wallet/serializer/`, each with round-trip specs.
- [ ] `Wire::Validation` covers every branded type; every failure raises `WERR_INVALID_PARAMETER`.
- [ ] `WalletWireTransceiver` implements `Interface::BRC100` over any `WalletWire`.
- [ ] `WalletWireProcessor` dispatches all 28 methods on any `Interface::BRC100`; loop-back test against `ProtoWallet` passes.
- [ ] `HTTPWalletJSON` and `HTTPWalletWire` substrates round-trip end-to-end against a `WebMock`-stubbed wallet.
- [ ] `WERR_*` exception classes with `code` attribute + `to_wire` helper; `error_from_wire` rehydrates them.
- [ ] Cross-SDK conformance vectors under `spec/conformance/brc103/` checked against fixtures captured from the Go SDK.
- [ ] `bundle exec rake spec:sdk` green.
- [ ] `bundle exec rubocop` green (with documented per-file relaxations under `serializer/`).
- [ ] `bsv-wallet#223` can `require 'bsv/wallet/wallet_wire_processor'` and wrap its `Engine` without further changes.

---

## Out of Scope (lifted from HLR)

- HTTP server / Rack app exposing an Engine — bsv-wallet#223.
- `LocalKVStore`, `StorageUploader`, `ContactsManager` — bsv-wallet#224.
- Browser substrates (`window.CWI`, XDM, RN) — TS-only.
- Permission system / `seek_permission` enforcement — engine concern.
- BRC-77 auth wrapping over the transport — composes with `bsv-402` Rack middleware externally.
