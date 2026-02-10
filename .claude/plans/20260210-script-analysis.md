# Script Analysis — Task #24

## Context

Issue #24, sub-task of HLR #8. Adds type detection predicates, a classification method, and data extraction to `Script`. Currently scripts have no introspection beyond raw chunk parsing.

Go SDK reference: `script/script.go` — `IsP2PKH`, `IsP2PK`, `IsP2SH`, `IsData`, `IsMultiSigOut`, `PublicKeyHash`, `Addresses`

---

## File Structure

```
lib/bsv/script/script.rb        # MODIFIED — add analysis methods
spec/bsv/script/script_spec.rb  # MODIFIED — add analysis tests
```

No new files needed. All methods are instance methods on `Script`.

---

## Implementation

All methods added to `BSV::Script::Script` between the serialisation and chunk-parsing sections.

### 1. Type predicates

Byte-level pattern matching for standard types (matching Go SDK exactly):

**`p2pkh?`** — 25 bytes: `OP_DUP OP_HASH160 <20 bytes> OP_EQUALVERIFY OP_CHECKSIG`
```ruby
def p2pkh?
  b = @bytes
  b.bytesize == 25 &&
    b.getbyte(0) == Opcodes::OP_DUP &&
    b.getbyte(1) == Opcodes::OP_HASH160 &&
    b.getbyte(2) == 0x14 &&
    b.getbyte(23) == Opcodes::OP_EQUALVERIFY &&
    b.getbyte(24) == Opcodes::OP_CHECKSIG
end
```

**`p2sh?`** — 23 bytes: `OP_HASH160 <20 bytes> OP_EQUAL`
```ruby
def p2sh?
  b = @bytes
  b.bytesize == 23 &&
    b.getbyte(0) == Opcodes::OP_HASH160 &&
    b.getbyte(1) == 0x14 &&
    b.getbyte(22) == Opcodes::OP_EQUAL
end
```

**`op_return?`** — starts with `OP_RETURN` or `OP_FALSE OP_RETURN`
```ruby
def op_return?
  b = @bytes
  (b.bytesize > 0 && b.getbyte(0) == Opcodes::OP_RETURN) ||
    (b.bytesize > 1 && b.getbyte(0) == Opcodes::OP_FALSE && b.getbyte(1) == Opcodes::OP_RETURN)
end
```

**`p2pk?`** — 2 chunks: `<compressed or uncompressed pubkey> OP_CHECKSIG`
```ruby
def p2pk?
  c = chunks
  return false unless c.length == 2 && c[0].data? && c[1].opcode == Opcodes::OP_CHECKSIG

  pubkey = c[0].data
  version = pubkey.getbyte(0)
  ((version == 0x02 || version == 0x03) && pubkey.bytesize == 33) ||
    ((version == 0x04 || version == 0x06 || version == 0x07) && pubkey.bytesize == 65)
end
```

**`multisig?`** — `OP_M <pubkeys...> OP_N OP_CHECKMULTISIG`
```ruby
def multisig?
  c = chunks
  return false if c.length < 3
  return false unless small_int_opcode?(c[0].opcode)
  return false unless small_int_opcode?(c[-2].opcode) && c[-1].opcode == Opcodes::OP_CHECKMULTISIG

  c[1..-3].all?(&:data?)
end
```

Private helper:
```ruby
def small_int_opcode?(op)
  op == Opcodes::OP_0 || (op >= Opcodes::OP_1 && op <= Opcodes::OP_16)
end
```

### 2. Type classification

```ruby
def type
  if @bytes.empty? then 'empty'
  elsif p2pkh? then 'pubkeyhash'
  elsif p2pk? then 'pubkey'
  elsif p2sh? then 'scripthash'
  elsif op_return? then 'nulldata'
  elsif multisig? then 'multisig'
  else 'nonstandard'
  end
end
```

Matching Go SDK string constants.

### 3. Data extraction

**`pubkey_hash`** — 20-byte PKH from P2PKH script (bytes 3-22)
```ruby
def pubkey_hash
  return unless p2pkh?
  @bytes.byteslice(3, 20)
end
```

**`script_hash`** — 20-byte script hash from P2SH script (bytes 2-21)
```ruby
def script_hash
  return unless p2sh?
  @bytes.byteslice(2, 20)
end
```

**`op_return_data`** — array of data payloads from OP_RETURN script
```ruby
def op_return_data
  return unless op_return?
  start = @bytes.getbyte(0) == Opcodes::OP_RETURN ? 1 : 2
  Script.new(@bytes.byteslice(start..)).chunks.select(&:data?).map(&:data)
end
```

**`addresses`** — extract addresses from known script types. Uses existing `BSV::Primitives::Base58.check_encode`.
```ruby
MAINNET_P2SH_PREFIX = "\x05".b.freeze
TESTNET_P2SH_PREFIX = "\xc4".b.freeze

def addresses(network: :mainnet)
  if p2pkh?
    prefix = network == :testnet ? BSV::Primitives::PublicKey::TESTNET_PUBKEY_HASH : BSV::Primitives::PublicKey::MAINNET_PUBKEY_HASH
    [BSV::Primitives::Base58.check_encode(prefix + pubkey_hash)]
  elsif p2sh?
    prefix = network == :testnet ? TESTNET_P2SH_PREFIX : MAINNET_P2SH_PREFIX
    [BSV::Primitives::Base58.check_encode(prefix + script_hash)]
  else
    []
  end
end
```

Reuses `PublicKey::MAINNET_PUBKEY_HASH` (`"\x00"`) and `PublicKey::TESTNET_PUBKEY_HASH` (`"\x6f"`) constants already defined in the SDK.

---

## Test Strategy

### Type predicates (`spec/bsv/script/script_spec.rb`)

**P2PKH:**
- `Script.p2pkh_lock(hash)` returns `p2pkh? == true`
- Non-P2PKH scripts return `false`

**P2SH:**
- Hand-crafted P2SH script (via builder) returns `p2sh? == true`
- P2PKH script returns `false`

**OP_RETURN:**
- `Script.op_return(data)` returns `op_return? == true`
- Both `OP_RETURN` and `OP_FALSE OP_RETURN` formats detected
- P2PKH returns `false`

**P2PK:**
- Compressed pubkey (33 bytes) + OP_CHECKSIG returns `p2pk? == true`
- Uncompressed pubkey (65 bytes) + OP_CHECKSIG returns `p2pk? == true`

**Multisig:**
- 2-of-3 multisig script returns `multisig? == true`
- P2PKH returns `false`

### Type classification

- `type` returns correct string for each script type
- Empty script returns `'empty'`
- Unknown script returns `'nonstandard'`

### Data extraction

- `pubkey_hash` returns 20 bytes from P2PKH, `nil` from non-P2PKH
- `script_hash` returns 20 bytes from P2SH, `nil` from non-P2SH
- `op_return_data` returns array of data items, `nil` from non-OP_RETURN
- `addresses` returns address array from P2PKH (mainnet and testnet)
- `addresses` returns address array from P2SH
- `addresses` returns empty array for unknown types

### Backward compatibility

All existing tests pass unchanged.

---

## Commit

Single commit: `feat(script): add type detection, predicates, and data extraction`

---

## Verification

```bash
bundle exec rspec spec/bsv/script/script_spec.rb
bundle exec rubocop lib/bsv/script/script.rb
bundle exec rake
```
