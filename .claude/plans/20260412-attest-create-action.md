# Plan: Rework bsv-attest to use wallet create_action (#390)

## Context

`bsv-attest` v0.1.0 was written before `bsv-wallet` existed. Its `publish` method calls `wallet.fund_and_sign(tx)` (doesn't exist) and requires a separate `broadcaster:`. The x402-rack companion gem demonstrates the correct pattern: delegate to `wallet.create_action`, letting the wallet handle funding, signing, broadcasting, and UTXO state.

This is an integration rework — the core hash/verify logic is sound and unchanged.

## Tasks

### Task 1: Update Configuration — remove `broadcaster:`, keep `wallet:` and `provider:`

**File:** `gem/bsv-attest/lib/bsv/attest/configuration.rb`

Remove `broadcaster` from `attr_accessor`. Configuration becomes:
```ruby
attr_accessor :wallet, :provider
```

**File:** `gem/bsv-attest/spec/bsv/attest/configuration_spec.rb`

Remove broadcaster-related specs, update the "supports setting all attributes" spec to cover only `wallet` and `provider`.

### Task 2: Update Response — replace `transaction` with `tx` and add `broadcast_status`

**File:** `gem/bsv-attest/lib/bsv/attest/response.rb`

Current: `attr_reader :hash, :transaction, :txid`

New:
```ruby
attr_reader :hash, :txid, :tx, :broadcast_status

def initialize(hash:, txid:, tx: nil, broadcast_status: nil)
  @hash = hash
  @txid = txid
  @tx = tx
  @broadcast_status = broadcast_status
end
```

- `tx` — BEEF bytes (Array<Integer>) from create_action, optional
- `broadcast_status` — string ('success', 'doubleSpend', etc.), optional
- `hash_hex` stays the same
- Drop `transaction` — we no longer build the Transaction object ourselves

**File:** `gem/bsv-attest/spec/bsv/attest/response_spec.rb`

Update to test the new attributes (`tx`, `broadcast_status`) instead of `transaction`.

### Task 3: Add BroadcastError class

**File:** `gem/bsv-attest/lib/bsv/attest/broadcast_error.rb` (new)

```ruby
class BroadcastError < StandardError; end
```

Raised when `create_action` returns a `broadcast_error` in its result. This gives callers a distinct exception type for broadcast failures vs argument errors.

**File:** `gem/bsv-attest/lib/bsv/attest.rb` — add autoload entry.

### Task 4: Rewrite `publish` to use `wallet.create_action`

**File:** `gem/bsv-attest/lib/bsv/attest.rb`

Current signature: `publish(data, wallet: nil, broadcaster: nil)`
New signature: `publish(data, wallet: nil, description: nil)`

Implementation:
```ruby
def publish(data, wallet: nil, description: nil)
  w = wallet || configuration.wallet
  raise ArgumentError, 'wallet is required' unless w

  digest = hash(data)
  script = BSV::Script::Script.op_return(digest)

  desc = description || 'Attest data hash to chain'

  result = w.create_action(
    description: desc,
    outputs: [{
      locking_script: script.to_hex,
      satoshis: 0,
      output_description: 'Attestation hash'
    }],
    options: { randomize_outputs: false }
  )

  if result[:broadcast_error]
    raise BroadcastError, result[:broadcast_error]
  end

  Response.new(
    hash: digest,
    txid: result[:txid],
    tx: result[:tx],
    broadcast_status: result[:broadcast_status]
  )
end
```

Key decisions:
- **No `broadcaster:` parameter** — wallet owns broadcasting
- **`description:` parameter** — optional override for the wallet action description (default: 'Attest data hash to chain', 26 chars, within 5-50 limit)
- **`randomize_outputs: false`** — deterministic output ordering (OP_RETURN first, then change)
- **BroadcastError on failure** — if the wallet returns broadcast_error, raise rather than return a partial response
- **`verify` unchanged** — provider-based verification is independent of the publish rework

### Task 5: Update gemspec and version

**File:** `gem/bsv-attest/bsv-attest.gemspec`

```ruby
spec.add_dependency 'bsv-sdk', '>= 0.11.0', '< 1.0'
spec.add_dependency 'bsv-wallet', '>= 0.7.0', '< 1.0'
```

The wallet is a runtime dependency because `publish` calls `create_action` directly. Version floors match current releases.

**File:** `gem/bsv-attest/lib/bsv/attest/version.rb`

Bump to `0.2.0` — breaking change (dropped broadcaster, changed Response shape).

### Task 6: Rewrite specs

**File:** `gem/bsv-attest/spec/bsv/attest_spec.rb`

**publish specs** — replace mock wallet/broadcaster with a mock that responds to `create_action`:

```ruby
let(:mock_wallet) do
  Class.new do
    def create_action(args)
      {
        txid: 'bb' * 32,
        tx: [0x01, 0x00],
        broadcast_status: 'success'
      }
    end
  end.new
end
```

Update specs:
- "builds an OP_RETURN transaction" → "delegates to create_action and returns Response"
- "includes the hash in an OP_RETURN output" → verify the create_action args include correct locking_script
- Remove "raises ArgumentError without broadcaster"
- Add "raises BroadcastError on broadcast failure"
- Add "passes custom description to create_action"
- Update per-call override spec (wallet only, no broadcaster)
- Update fallback spec (wallet only)
- Keep verify specs unchanged (they test provider, not wallet)

To verify create_action receives the correct output spec, use a spy-style mock:

```ruby
let(:spy_wallet) do
  Class.new do
    attr_reader :last_args
    def create_action(args)
      @last_args = args
      { txid: 'bb' * 32, tx: [0x01], broadcast_status: 'success' }
    end
  end.new
end
```

Then assert `spy_wallet.last_args[:outputs].first[:locking_script]` contains the expected OP_RETURN hex.

## Files Modified

| File | Action |
|------|--------|
| `gem/bsv-attest/lib/bsv/attest.rb` | Edit: rewrite publish, add autoloads |
| `gem/bsv-attest/lib/bsv/attest/configuration.rb` | Edit: remove broadcaster |
| `gem/bsv-attest/lib/bsv/attest/response.rb` | Edit: replace transaction with tx + broadcast_status |
| `gem/bsv-attest/lib/bsv/attest/broadcast_error.rb` | New: BroadcastError class |
| `gem/bsv-attest/lib/bsv/attest/version.rb` | Edit: bump to 0.2.0 |
| `gem/bsv-attest/bsv-attest.gemspec` | Edit: add bsv-wallet dep, pin bsv-sdk |
| `gem/bsv-attest/spec/bsv/attest_spec.rb` | Edit: rewrite publish specs |
| `gem/bsv-attest/spec/bsv/attest/configuration_spec.rb` | Edit: remove broadcaster specs |
| `gem/bsv-attest/spec/bsv/attest/response_spec.rb` | Edit: test new attributes |

## Verification

```bash
cd gem/bsv-attest && bundle exec rspec    # all specs pass
bundle exec rubocop gem/bsv-attest        # no offences
cd gem/bsv-attest && gem build bsv-attest.gemspec  # gem builds
```
