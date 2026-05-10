# Plan: Refactor Protocol to compose Net::HTTPResponse (#742)

## Context

`BSV::Network::Protocol` reimplements what `Net::HTTP` already provides. The `Result::Success/Error/NotFound` module forces a non-standard interface (`data`, `message`, custom predicates) when Ruby developers expect `.body` and `.code`. The refactor replaces `Result` with a single `ProtocolResponse` class that composes `Net::HTTPResponse` with progressive enhancement layers: raw HTTP -> parsed data -> canonical form.

## ProtocolResponse Design

```ruby
class ProtocolResponse
  attr_reader :data, :error_message

  def initialize(http_response, data: nil, ok: nil, error_message: nil)
    @http_response = http_response
    @data = data
    @ok = ok.nil? ? http_response&.is_a?(Net::HTTPSuccess) : ok
    @error_message = error_message
    freeze
  end

  # Delegated from Net::HTTPResponse (nil-safe)
  def body;         @http_response&.body; end
  def code;         @http_response&.code; end
  def content_type; @http_response&.content_type; end

  # Status predicates
  def success?;   @ok; end
  def error?;     !@ok; end
  def not_found?; @http_response.is_a?(Net::HTTPNotFound); end
  def retryable?
    @http_response.is_a?(Net::HTTPTooManyRequests) ||
      @http_response.is_a?(Net::HTTPServerError)
  end

  # Canonical form (placeholder — delegates to data until #77 defines shapes)
  def canonical; data; end

  # Compatibility: chain trackers + MCP tools call .message
  alias message error_message

  # Derive new response with overrides (same HTTP response, different interpretation)
  def with(**overrides)
    self.class.new(
      @http_response,
      data: overrides.fetch(:data, @data),
      ok: overrides.fetch(:ok, @ok),
      error_message: overrides.fetch(:error_message, @error_message)
    )
  end
end
```

**Key decisions:**
- `ok:` defaults to HTTP success status but is overridable (ARC REJECTED-on-2xx -> ok: false; WoC is_utxo-404 -> ok: true)
- `not_found?` and `retryable?` always reflect HTTP transport status, independent of logical `ok:`
- `error?` added (inverse of `success?`) for chain tracker compatibility
- `message` aliased to `error_message` for chain tracker + MCP tool compatibility
- Nil HTTP response accepted for edge cases (empty batch early returns)
- Frozen after construction (immutable like Result was)
- No `metadata` hash — `.code` replaces `metadata[:status_code]`

## Blast Radius

Result consumers beyond the Network module:
- **Chain trackers** (`lib/bsv/transaction/chain_trackers/{chaintracks,whats_on_chain}.rb`) — use `.error?`, `.not_found?`, `.message`, `.metadata[:status_code]`, `.data`, `.success?`
- **MCP tools** (`lib/bsv/mcp/tools/{broadcast_p2pkh,fetch_tx,check_balance,fetch_utxos}.rb`) — use `.success?`, `.message`, `.metadata[:status_code]`, `.data`, `.data[:txid]` (symbol keys from `arc_data_from`)

## Test Helper

All specs currently use `Struct.new(:code, :body)` or `instance_double(Net::HTTPResponse)` for fake responses. These won't pass `is_a?(Net::HTTPSuccess)` etc. A shared helper is needed:

```ruby
# spec/support/fake_http_response.rb
def fake_http_response(code, body, content_type: nil)
  klass = Net::HTTPResponse::CODE_TO_OBJ[code.to_s]
  response = klass.new('1.1', code.to_s, '')
  response.instance_variable_set(:@body, body)
  response.instance_variable_set(:@read, true)
  response['Content-Type'] = content_type if content_type
  response
end
```

---

## Tasks

### Task 1: Create ProtocolResponse class + test helper

**New files:**
- `gem/bsv-sdk/lib/bsv/network/protocol_response.rb` — class as designed above
- `gem/bsv-sdk/spec/support/fake_http_response.rb` — shared test helper
- `gem/bsv-sdk/spec/bsv/network/protocol_response_spec.rb` — full spec coverage

**Edit:**
- `gem/bsv-sdk/lib/bsv/network.rb` — add `autoload :ProtocolResponse, 'bsv/network/protocol_response'`

**Depends on:** nothing

### Task 2: Refactor Protocol base class

**Edit:** `gem/bsv-sdk/lib/bsv/network/protocol.rb`
- Rename `map_response` -> `build_response`, return `ProtocolResponse`:
  - 2xx: parse body via `apply_handler`, wrap in `ProtocolResponse.new(response, data: parsed)`
  - 2xx + parse error: `ProtocolResponse.new(response, ok: false, error_message: "JSON/response error: #{e.message}")`
  - Non-2xx: `ProtocolResponse.new(response, error_message: response.body)`
- `apply_handler` — remove `Result::Error` rescue; let exceptions propagate to `build_response`
- `default_call` — calls `build_response` instead of `map_response`
- Update `@return` docs throughout

**Edit:** `gem/bsv-sdk/spec/bsv/network/protocol_spec.rb`
- Replace `Struct.new(:code, :body)` fake responses with `fake_http_response`
- Replace `be_a(Result::Success)` with predicate checks (`be_success` etc.)
- Replace `.data` assertions where needed

**Edit:** `gem/bsv-sdk/spec/bsv/network/protocol_integration_spec.rb`
- Same pattern of Result class checks -> predicate checks

**Depends on:** Task 1

### Task 3: Refactor ARC escape hatches

**Edit:** `gem/bsv-sdk/lib/bsv/network/protocols/arc.rb`
- `parse_single_broadcast_response` -> returns `ProtocolResponse`:
  - Rejected: `ProtocolResponse.new(response, ok: false, error_message: ..., data: body)`
  - Malformed 2xx: `ProtocolResponse.new(response, ok: false, error_message: ...)`
  - Success: `ProtocolResponse.new(response, data: body)` — raw JSON, **no `arc_data_from`**
  - Non-2xx: `ProtocolResponse.new(response, ok: false, error_message: ...)`
- `parse_batch_broadcast_response` -> returns `ProtocolResponse`:
  - HTTP error: `ProtocolResponse.new(response, ok: false, error_message: ...)`
  - Success: `ProtocolResponse.new(response, data: raw_array)` — raw JSON array, no per-item Result wrapping
- `call_broadcast_many` empty case: `ProtocolResponse.new(nil, data: [], ok: true)`
- `call_get_tx_status` -> uses `response.with(ok: false, ...)` pattern for rejection
- **Remove** `arc_data_from` method
- **Remove** `build_item_result` method

**Edit:** `gem/bsv-sdk/spec/bsv/network/protocols/arc_spec.rb`
- All `Result::` references -> predicate checks
- `.data[:txid]` -> `.data['txid']` (raw JSON string keys)
- Per-item batch assertions: raw hashes instead of Result objects
- Use `fake_http_response` for mock responses

**Edit:** `gem/bsv-sdk/spec/bsv/network/protocols/arc_integration_spec.rb` — same pattern

**Depends on:** Task 2

### Task 4: Refactor WoCREST escape hatches

**Edit:** `gem/bsv-sdk/lib/bsv/network/protocols/woc_rest.rb`
- `call_is_utxo` -> `result.with(data: true, ok: true)` for 404, `result.with(data: false)` for 200
- `call_is_utxo_bulk` -> empty: `ProtocolResponse.new(nil, data: {}, ok: true)`, else `result.with(data: normalised)`
- `call_broadcast` -> `result.with(data: { txid: result.data.to_s.strip })`
- `call_valid_root` -> `result.with(data: boolean)`
- Body-formatting escape hatches (10+): no source changes needed — they delegate to `default_call` which now returns ProtocolResponse

**Edit:** `gem/bsv-sdk/spec/bsv/network/protocols/woc_rest_spec.rb` — 135 `Result::` references -> predicate checks, `fake_http_response`

**Edit:** `gem/bsv-sdk/spec/bsv/network/protocols/woc_rest_integration_spec.rb` — same pattern

**Depends on:** Task 2. **Parallel with** Task 3.

### Task 5: Refactor TAALBinary + Ordinals escape hatches

**Edit:** `gem/bsv-sdk/lib/bsv/network/protocols/taal_binary.rb`
- `parse_broadcast_response` -> returns `ProtocolResponse`
- `already_known?` quirk: `ProtocolResponse.new(response, data: { txid: body['txid'] }, ok: true)`

**Edit:** `gem/bsv-sdk/lib/bsv/network/protocols/ordinals.rb`
- `call_get_tx` -> `result.with(data: hex_string)` or `result.with(ok: false, error_message: ...)`
- `call_get_spend` -> `result.with(data: { spent: false/true })` or `result.with(ok: false, ...)`

**Edit specs:** `taal_binary_spec.rb`, `ordinals_spec.rb`, `ordinals_integration_spec.rb`

**Depends on:** Task 2. **Parallel with** Tasks 3, 4.

### Task 6: Update remaining protocols + Provider

**Edit:** `gem/bsv-sdk/lib/bsv/network/provider.rb` — update `@return` docs only (pure passthrough, no code changes)

**Edit specs:** `provider_spec.rb`, `chaintracks_spec.rb`, `jungle_bus_spec.rb`, `jungle_bus_integration_spec.rb`, `all_protocols_spec.rb`

**Depends on:** Task 2. **Parallel with** Tasks 3-5.

### Task 7: Update external consumers

**Edit chain trackers:**
- `gem/bsv-sdk/lib/bsv/transaction/chain_trackers/chaintracks.rb` — `result.metadata[:status_code]` -> `result.code`
- `gem/bsv-sdk/lib/bsv/transaction/chain_trackers/whats_on_chain.rb` — same

**Edit MCP tools:**
- `gem/bsv-sdk/lib/bsv/mcp/tools/broadcast_p2pkh.rb` — `.data[:txid]` -> `.data['txid']`, `.data[:tx_status]` -> `.data['txStatus']`
- `gem/bsv-sdk/lib/bsv/mcp/tools/fetch_tx.rb` — `.metadata[:status_code]` -> `.code`
- `gem/bsv-sdk/lib/bsv/mcp/tools/check_balance.rb` — same
- `gem/bsv-sdk/lib/bsv/mcp/tools/fetch_utxos.rb` — same

**Edit specs:** chain tracker specs (use `fake_http_response`), MCP tool specs (update mock responses and assertions)

**Edit:** `gem/bsv-sdk/spec/integration/testnet_spec.rb` — update Result references

**Depends on:** Tasks 3-6 (all protocols migrated)

### Task 8: Remove Result module + cleanup

**Delete:**
- `gem/bsv-sdk/lib/bsv/network/result.rb`
- `gem/bsv-sdk/spec/bsv/network/result_spec.rb`

**Edit:**
- `gem/bsv-sdk/lib/bsv/network.rb` — remove `autoload :Result`
- `gem/bsv-sdk/lib/bsv/network/arc.rb` — update deprecation message (mentions "Result objects")
- `gem/bsv-sdk/lib/bsv/network/whats_on_chain.rb` — update deprecation message

**Depends on:** All other tasks complete

## Dependency Graph

```
Task 1 (ProtocolResponse + helper)
  |
Task 2 (Protocol base class)
  |
  +--------+--------+--------+
  |        |        |        |
Task 3   Task 4   Task 5   Task 6    (parallel)
 (ARC)   (WoC)  (TAAL+Ord) (Provider+CT+JB)
  |        |        |        |
  +--------+--------+--------+
           |
        Task 7 (chain trackers + MCP tools)
           |
        Task 8 (remove Result)
```

## Verification

After each task: `bundle exec rspec` (full suite)
After Task 8: `bundle exec rubocop` + `bundle exec rspec` — zero Result references remaining
Grep check: `grep -r 'Result::' gem/bsv-sdk/lib/` should return zero matches (excluding the word "result" in non-class contexts)
