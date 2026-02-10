# UnlockingScriptTemplate Pattern — Task #20

## Context

Issue #20, sub-task of HLR #11. Implements a pluggable signing interface for custom script types, following the Go SDK's `UnlockingScriptTemplate` pattern. Currently only hardcoded P2PKH signing is supported via `Transaction#sign`.

Go SDK reference: `transaction/script_template.go` (interface), `transaction/template/p2pkh/p2pkh.go` (P2PKH impl)

---

## File Structure

```
lib/bsv/transaction/unlocking_script_template.rb  # NEW — base class
lib/bsv/transaction/p2pkh.rb                      # NEW — P2PKH template
lib/bsv/transaction.rb                            # MODIFIED — add autoloads
lib/bsv/transaction/transaction_input.rb           # MODIFIED — add template accessor
lib/bsv/transaction/transaction.rb                 # MODIFIED — template-aware signing + fee estimation
spec/bsv/transaction/p2pkh_spec.rb                 # NEW — P2PKH template tests
spec/bsv/transaction/transaction_spec.rb           # MODIFIED — template integration tests
```

---

## Implementation

### 1. Base class: `UnlockingScriptTemplate`

`lib/bsv/transaction/unlocking_script_template.rb` — `BSV::Transaction::UnlockingScriptTemplate`

```ruby
class UnlockingScriptTemplate
  def sign(tx, input_index)
    raise NotImplementedError, "#{self.class}#sign must be implemented"
  end

  def estimated_length(_tx, _input_index)
    raise NotImplementedError, "#{self.class}#estimated_length must be implemented"
  end
end
```

Two methods matching Go SDK interface:
- `sign(tx, input_index)` — returns a `BSV::Script::Script` (the unlocking script)
- `estimated_length(tx, input_index)` — returns Integer (estimated unlocking script byte size, for fee calculation)

### 2. P2PKH template

`lib/bsv/transaction/p2pkh.rb` — `BSV::Transaction::P2PKH < UnlockingScriptTemplate`

```ruby
class P2PKH < UnlockingScriptTemplate
  ESTIMATED_SCRIPT_LENGTH = 107  # 1 + ~72 (DER sig+hashtype) + 1 + 33 (compressed pubkey)

  def initialize(private_key, sighash_type: Sighash::ALL_FORK_ID)
    @private_key = private_key
    @sighash_type = sighash_type
  end

  def sign(tx, input_index)
    hash = tx.sighash(input_index, @sighash_type)
    signature = @private_key.sign(hash)
    sig_with_hashtype = signature.to_der + [@sighash_type].pack('C')
    pubkey_bytes = @private_key.public_key.compressed
    BSV::Script::Script.p2pkh_unlock(sig_with_hashtype, pubkey_bytes)
  end

  def estimated_length(_tx, _input_index)
    ESTIMATED_SCRIPT_LENGTH
  end
end
```

Logic extracted directly from existing `Transaction#sign` (lines 167-176 of transaction.rb).

### 3. Add autoloads

`lib/bsv/transaction.rb` — add two new autoloads:

```ruby
autoload :UnlockingScriptTemplate, 'bsv/transaction/unlocking_script_template'
autoload :P2PKH,                   'bsv/transaction/p2pkh'
```

### 4. Add template accessor to `TransactionInput`

`lib/bsv/transaction/transaction_input.rb` — add to `attr_accessor` line:

```ruby
attr_accessor :unlocking_script, :source_satoshis, :source_locking_script,
              :source_transaction, :unlocking_script_template
```

### 5. Modify `Transaction` signing and fee estimation

`lib/bsv/transaction/transaction.rb`:

**`sign_all`** — make `private_key` optional, check templates first:

```ruby
def sign_all(private_key = nil, sighash_type = Sighash::ALL_FORK_ID)
  @inputs.each_with_index do |input, index|
    next if input.unlocking_script

    if input.unlocking_script_template
      input.unlocking_script = input.unlocking_script_template.sign(self, index)
    elsif private_key
      sign(index, private_key, sighash_type)
    end
  end
  self
end
```

Backward compatible: existing callers always pass `private_key`, so behaviour is unchanged. New callers can pass `nil` (or omit) to use templates only.

**`sign`** — unchanged (still the single-input P2PKH convenience method).

**`estimated_size`** — use template's `estimated_length` when available:

```ruby
def estimated_size
  size = 4 # version
  size += VarInt.encode(@inputs.length).bytesize
  @inputs.each_with_index do |input, index|
    size += if input.unlocking_script
              input.to_binary.bytesize
            elsif input.unlocking_script_template
              script_len = input.unlocking_script_template.estimated_length(self, index)
              32 + 4 + VarInt.encode(script_len).bytesize + script_len + 4
            else
              UNSIGNED_P2PKH_INPUT_SIZE
            end
  end
  size += VarInt.encode(@outputs.length).bytesize
  @outputs.each { |o| size += o.to_binary.bytesize }
  size += 4 # lock_time
  size
end
```

---

## Test Strategy

### P2PKH template unit tests (`spec/bsv/transaction/p2pkh_spec.rb`)

- `#sign` produces valid unlocking script (2 chunks: signature + pubkey)
- `#sign` signature ends with sighash type byte
- `#sign` pubkey is 33 bytes (compressed)
- `#sign` with custom sighash type uses that type
- `#estimated_length` returns 107

### Template integration tests (`spec/bsv/transaction/transaction_spec.rb`)

- **Template-based signing matches direct signing**: build same tx, sign one with `tx.sign(0, key)` and other with P2PKH template on input + `tx.sign_all`, compare hex output
- **`sign_all` with templates only (no private_key)**: inputs with templates get signed
- **`sign_all` mixed mode**: some inputs have templates, others rely on private_key fallback
- **`sign_all` skips already-signed inputs**: inputs with existing unlocking_script are untouched
- **Fee estimation with templates**: `estimated_fee` uses template's `estimated_length` instead of P2PKH constant

### Backward compatibility

All existing `#sign` / `#sign_all` / signing tests pass unchanged.

---

## Commit

Single commit: `feat(transaction): add UnlockingScriptTemplate pattern for pluggable signing`

---

## Verification

```bash
bundle exec rspec spec/bsv/transaction/p2pkh_spec.rb
bundle exec rspec spec/bsv/transaction/transaction_spec.rb
bundle exec rubocop lib/bsv/transaction/unlocking_script_template.rb lib/bsv/transaction/p2pkh.rb lib/bsv/transaction/transaction_input.rb lib/bsv/transaction/transaction.rb
bundle exec rake
```
