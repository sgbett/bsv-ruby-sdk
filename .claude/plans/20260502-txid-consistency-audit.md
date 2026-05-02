# Txid Consistency Audit: Validation, Instrumentation, and Type Safety

## Context

The SDK recently adopted a wtxid/dtxid naming convention to eliminate byte-order ambiguity in transaction IDs. The bulk rename was mechanical — this audit examines every non-trivial txid codepath for subtle bugs, adds validation guards at unprotected entry points, and introduces debug-level instrumentation to help future developers trace byte-order conversions.

## Analysis Findings

### Confirmed Correct (no changes needed)

- **All internal comparisons** (`==`) operate on wire-order binary — no byte-order mismatches
- **All hash-table keys** (`verified[wtxid]`, `seen[wtxid]`, `wtxid_index[bt.wtxid]`, `tx_map[input.prev_wtxid]`) consistently use wire-order binary
- **All boundary conversions** (display↔wire) use the correct pattern: `.reverse.unpack1('H*')` for wire→display, `[hex].pack('H*').reverse` for display→wire
- **Certificate `revocation_outpoint`** serialisation stores display-byte-order txid in binary — matches Go SDK (which `WriteBytesReverse`s wire-order to display-order) and TS SDK (which packs display-hex directly). All three SDKs are consistent.
- **BEEF dependency ordering**, merkle path computation, and Atomic BEEF subject_wtxid are all internally consistent

### Issues Found

#### 1. Missing `validate_dtxid_hex!` in `MerklePath#compute_root_hex` (merkle_path.rb:299)

`compute_root_hex(dtxid_hex)` converts the optional hex parameter via `[dtxid_hex].pack('H*').reverse` without validation. A malformed string (wrong length, non-hex chars) silently produces garbage — `pack('H*')` truncates odd-length strings and drops non-hex characters.

#### 2. Missing hex validation in `MerklePath.tsc_path_element` (merkle_path.rb:196-201)

TSC node hex strings from the WhatsOnChain API are converted via `[node].pack('H*').reverse` without any validation. Malformed WoC responses silently produce corrupt merkle paths.

#### 3. Missing validation in `MerklePath.from_tsc` nodes array (merkle_path.rb:167-188)

The `nodes` parameter is iterated and each element is passed to `tsc_path_element` without checking that non-`"*"` entries are valid 64-char hex strings.

#### 4. No debug instrumentation at txid conversion points

The SDK has no logging infrastructure. When developers encounter byte-order issues, there's no way to trace which format a value was in at each step.

#### 5. Missing validation in `UTXO.tx_hash` → `wtxid_from_hex` chain

`UTXO#tx_hash` is a plain string attribute with no format validation. While `wtxid_from_hex` validates its input, the UTXO constructor does not, meaning corrupt data propagates until the `wtxid_from_hex` call — possibly far from the source.

## Plan

### 1. Add `BSV.logger` infrastructure (`lib/bsv-sdk.rb`)

Add a module-level logger accessor to BSV:

```ruby
module BSV
  class << self
    attr_writer :logger
    def logger
      @logger
    end
  end
end
```

No default logger — zero overhead when not configured. Consumers opt in via `BSV.logger = Logger.new($stdout, level: :debug)`.

### 2. Add validation to `MerklePath#compute_root_hex` (`merkle_path.rb:299`)

Validate the optional `dtxid_hex` parameter before conversion:

```ruby
def compute_root_hex(dtxid_hex = nil)
  if dtxid_hex
    BSV::Primitives::Hex.validate_dtxid_hex!(dtxid_hex, name: 'compute_root_hex dtxid_hex')
  end
  wtxid = dtxid_hex ? [dtxid_hex].pack('H*').reverse : nil
  compute_root(wtxid).reverse.unpack1('H*')
end
```

### 3. Add validation to `MerklePath.from_tsc` and `tsc_path_element` (`merkle_path.rb`)

Validate each non-`"*"` node string as a 64-char hex value:

```ruby
def self.tsc_path_element(node, offset)
  if node == '*'
    PathElement.new(offset: offset, duplicate: true)
  else
    BSV::Primitives::Hex.validate_dtxid_hex!(node, name: 'TSC merkle node')
    PathElement.new(offset: offset, hash: [node].pack('H*').reverse)
  end
end
```

### 4. Add debug logging at key conversion points

Add `BSV.logger&.debug` calls at:

- **`TransactionInput#initialize`** — log when prev_wtxid is set (with dtxid_hex for readability)
- **`TransactionInput.wtxid_from_hex`** — log the display→wire conversion
- **`Transaction#wtxid`** — log the computed wtxid (display hex)
- **`MerklePath#compute_root`** — log the input wtxid and computed root
- **`MerklePath#verify`** — log the verification result with dtxid_hex and block height
- **`Beef.wire_source_transactions`** — log each prev_wtxid→source wiring
- **`Beef#find_transaction`** — log lookup attempts and results

Keep messages terse: `"[BSV::Transaction] wtxid computed: #{dtxid_hex}"` format. Guard every call with `BSV.logger&.debug` (safe navigation) so the cost is a single nil check when logging is disabled.

### 5. Add `validate_hash32!` convenience method to `Hex` (`hex.rb`)

A general-purpose 32-byte binary hash validator, for use in merkle path elements and other non-txid contexts where a 32-byte hash is expected:

```ruby
def self.validate_hash32!(value, name: 'hash')
  unless value.is_a?(String) && value.bytesize == 32
    hint = if value.is_a?(String) && value.bytesize == 64 && value.match?(HEX_RE)
             ' (looks like hex — decode it first)'
           else
             ''
           end
    size = value.is_a?(String) ? "#{value.bytesize}-byte string" : value.class.to_s
    raise ArgumentError,
          "expected 32-byte hash for #{name}, got #{size}#{hint}"
  end
  value
end
```

Use this in `MerklePath::PathElement` construction where `hash:` is provided, and in `MerklePath#compute_root` for the auto-detected hash.

### 6. Boundary comment for certificate serialisation (`certificate.rb:84`)

Add a comment documenting that the revocation_outpoint txid is stored in display byte order in the binary format, matching all reference SDKs:

```ruby
# Certificate binary format: revocation outpoint txid stored in display byte
# order (matching TS and Go SDKs). Go encodes via WriteBytesReverse(wire_order),
# TS encodes via toArray(display_hex) — both produce identical display-order bytes.
```

## Files Modified

| File | Change |
|------|--------|
| `gem/bsv-sdk/lib/bsv-sdk.rb` | Add `BSV.logger` accessor |
| `gem/bsv-sdk/lib/bsv/primitives/hex.rb` | Add `validate_hash32!` method |
| `gem/bsv-sdk/lib/bsv/transaction/merkle_path.rb` | Add validation to `compute_root_hex`, `from_tsc`, `tsc_path_element` + debug logging |
| `gem/bsv-sdk/lib/bsv/transaction/transaction.rb` | Debug logging in `wtxid` |
| `gem/bsv-sdk/lib/bsv/transaction/transaction_input.rb` | Debug logging in `initialize`, `wtxid_from_hex` |
| `gem/bsv-sdk/lib/bsv/transaction/beef.rb` | Debug logging in `find_transaction`, `wire_source_transactions` |
| `gem/bsv-sdk/lib/bsv/auth/certificate.rb` | Boundary comment on byte order |
| `gem/bsv-sdk/spec/bsv/transaction/merkle_path_spec.rb` | Tests for new validation behaviour |
| `gem/bsv-sdk/spec/bsv/primitives/hex_spec.rb` | Tests for `validate_hash32!` |

## Verification

```bash
bundle exec rake spec:sdk   # all existing specs must pass
bundle exec rubocop          # lint check
```

Specific validation tests:
- `compute_root_hex` raises `ArgumentError` on malformed hex input
- `from_tsc` raises `ArgumentError` on non-hex node strings
- `validate_hash32!` rejects non-32-byte inputs with helpful hints
- Debug logging produces output when `BSV.logger` is set (visual check)
