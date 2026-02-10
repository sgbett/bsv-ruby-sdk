# ScriptBuilder Fluent API — Task #23

## Context

Issue #23, sub-task of HLR #8. Adds a chainable builder for programmatic script construction. Currently scripts are built via static template methods (`p2pkh_lock`, `op_return`) or from raw binary/hex/ASM. No way to construct arbitrary scripts incrementally.

Go SDK reference: `script/script.go` — `AppendPushData`, `AppendOpcodes`, `AppendPushDataHex`, etc.

---

## File Structure

```
lib/bsv/script/builder.rb        # NEW — Builder class
lib/bsv/script.rb                # MODIFIED — add autoload
spec/bsv/script/builder_spec.rb  # NEW — tests
```

---

## Implementation

### 1. Builder class

`lib/bsv/script/builder.rb` — `BSV::Script::Builder`

Accumulates `Chunk` objects, returns a `Script` via `#build`. Each method returns `self` for chaining.

```ruby
class Builder
  def initialize
    @chunks = []
  end

  # Push an opcode by symbol (:OP_DUP) or integer (0x76)
  def push_op(opcode)
    code = opcode.is_a?(Symbol) ? Opcodes.const_get(opcode) : opcode
    @chunks << Chunk.new(opcode: code)
    self
  end

  # Push raw binary data (handles all PUSHDATA encodings)
  def push_data(data)
    bytes = data.b
    @chunks << Chunk.new(opcode: push_opcode_for(bytes.bytesize), data: bytes)
    self
  end

  # Push hex-encoded data
  def push_hex(hex)
    push_data([hex].pack('H*'))
  end

  def build
    Script.from_chunks(@chunks)
  end

  private

  def push_opcode_for(len)
    if len <= 0x4b
      len
    elsif len <= 0xff
      Opcodes::OP_PUSHDATA1
    elsif len <= 0xffff
      Opcodes::OP_PUSHDATA2
    else
      Opcodes::OP_PUSHDATA4
    end
  end
end
```

Uses `Chunk` as the encoding layer — `Chunk#to_binary` already handles all PUSHDATA variants correctly. `Script.from_chunks` joins chunk binaries into a Script.

### 2. Factory method on Script

`lib/bsv/script/script.rb` — add convenience entry point:

```ruby
def self.builder
  Builder.new
end
```

### 3. Autoload

`lib/bsv/script.rb` — add:

```ruby
autoload :Builder, 'bsv/script/builder'
```

---

## Test Strategy

### Builder unit tests (`spec/bsv/script/builder_spec.rb`)

**Core API:**
- `push_op` with symbol (`:OP_DUP`) appends correct opcode byte
- `push_op` with integer (`0x76`) appends correct opcode byte
- `push_data` with small data (<=75 bytes) uses direct push
- `push_data` with 76-255 bytes uses OP_PUSHDATA1
- `push_data` with 256+ bytes uses OP_PUSHDATA2
- `push_hex` converts hex to binary and pushes
- `build` returns a `BSV::Script::Script` instance

**Chaining:**
- Methods return self (builder pattern)
- Chained calls produce correct combined script

**Round-trip equivalence:**
- Builder-constructed P2PKH matches `Script.p2pkh_lock` output
- Builder-constructed OP_RETURN matches `Script.op_return` output

**Edge cases:**
- Empty builder produces empty script
- `push_op` raises `NameError` for unknown symbol

---

## Commit

Single commit: `feat(script): add Builder fluent API for programmatic script construction`

---

## Verification

```bash
bundle exec rspec spec/bsv/script/builder_spec.rb
bundle exec rubocop lib/bsv/script/builder.rb
bundle exec rake
```
