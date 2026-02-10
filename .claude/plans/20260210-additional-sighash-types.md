# Additional SIGHASH Types — Task #19

## Context

Issue #19, sub-task of HLR #11. Extends BIP-143 (FORKID) sighash computation to support NONE, SINGLE, ANYONE_CAN_PAY, and their combinations. Currently only `SIGHASH_ALL|FORKID` (0x41) is implemented.

Go SDK: `transaction/signaturehash.go` lines 58-149

---

## File Structure

```
lib/bsv/transaction/sighash.rb        # MODIFIED — add convenience constants
lib/bsv/transaction/transaction.rb    # MODIFIED — conditional hash logic in sighash_preimage
spec/bsv/transaction/transaction_spec.rb  # MODIFIED — add sighash tests
```

No new files needed.

---

## Implementation

### 1. Add convenience constants to `Sighash` module

`lib/bsv/transaction/sighash.rb`:

```ruby
module Sighash
  ALL             = 0x01
  NONE            = 0x02
  SINGLE          = 0x03
  ANYONE_CAN_PAY  = 0x80
  FORK_ID         = 0x40
  MASK            = 0x1f

  ALL_FORK_ID     = ALL | FORK_ID             # 0x41
  NONE_FORK_ID    = NONE | FORK_ID            # 0x42
  SINGLE_FORK_ID  = SINGLE | FORK_ID          # 0x43

  ALL_FORK_ID_ANYONE_CAN_PAY    = ALL_FORK_ID | ANYONE_CAN_PAY      # 0xC1
  NONE_FORK_ID_ANYONE_CAN_PAY   = NONE_FORK_ID | ANYONE_CAN_PAY     # 0xC2
  SINGLE_FORK_ID_ANYONE_CAN_PAY = SINGLE_FORK_ID | ANYONE_CAN_PAY   # 0xC3
end
```

### 2. Modify `sighash_preimage` and private hash methods

`lib/bsv/transaction/transaction.rb`:

Pass `sighash_type` to the three hash methods and apply BIP-143 conditional logic (matching Go SDK `CalcInputPreimage` lines 79-97):

**hashPrevouts** (field 2):
- Default: SHA256d of all input outpoints
- If `ANYONE_CAN_PAY` is set: 32 zero bytes

**hashSequence** (field 3):
- Default: SHA256d of all input sequences
- If `ANYONE_CAN_PAY` is set, OR base type is `NONE` or `SINGLE`: 32 zero bytes

**hashOutputs** (field 8):
- If base type is `ALL`: SHA256d of all outputs (current behaviour)
- If base type is `NONE`: 32 zero bytes
- If base type is `SINGLE`:
  - If `input_index < outputs.length`: SHA256d of output at `input_index` only
  - Else: 32 zero bytes (consensus edge case)

Base type is extracted via `sighash_type & MASK` (lower 5 bits).

Refactored method signatures:

```ruby
def sighash_preimage(input_index, sighash_type = Sighash::ALL_FORK_ID)
  raise ArgumentError, '...' unless sighash_type & Sighash::FORK_ID != 0

  input = @inputs[input_index]
  base_type = sighash_type & Sighash::MASK
  anyone = sighash_type & Sighash::ANYONE_CAN_PAY != 0

  buf = [@version].pack('V')
  buf << hash_prevouts(anyone)
  buf << hash_sequence(anyone, base_type)
  buf << input.outpoint_binary
  # ... scriptCode, value, nSequence unchanged ...
  buf << hash_outputs(base_type, input_index)
  buf << [@lock_time].pack('V')
  buf << [sighash_type].pack('V')
  buf
end

private

ZERO_HASH = ("\x00".b * 32).freeze

def hash_prevouts(anyone_can_pay)
  return ZERO_HASH if anyone_can_pay

  buf = @inputs.map(&:outpoint_binary).join
  BSV::Primitives::Digest.sha256d(buf)
end

def hash_sequence(anyone_can_pay, base_type)
  return ZERO_HASH if anyone_can_pay || base_type == Sighash::SINGLE || base_type == Sighash::NONE

  buf = @inputs.map { |i| [i.sequence].pack('V') }.join
  BSV::Primitives::Digest.sha256d(buf)
end

def hash_outputs(base_type, input_index)
  case base_type
  when Sighash::ALL
    buf = @outputs.map(&:to_binary).join
    BSV::Primitives::Digest.sha256d(buf)
  when Sighash::SINGLE
    if input_index < @outputs.length
      BSV::Primitives::Digest.sha256d(@outputs[input_index].to_binary)
    else
      ZERO_HASH
    end
  else # NONE
    ZERO_HASH
  end
end
```

---

## Test Strategy

The Go SDK test vectors only cover `SIGHASH_ALL|FORKID`. For the new types, use **structural verification**: build a transaction with known inputs/outputs, compute preimages for each sighash type, and verify the specific fields (hashPrevouts/hashSequence/hashOutputs) match expected values.

### Test setup

Reuse the existing test transaction (vector 1: 1 input, 2 outputs) already in the spec. Extract its known hashPrevouts, hashSequence, hashOutputs from the existing ALL|FORKID preimage, then verify:

### Tests to add

**NONE|FORKID (0x42):**
- hashPrevouts = same as ALL (all outpoints)
- hashSequence = 32 zero bytes
- hashOutputs = 32 zero bytes
- Fields 1, 4-7, 9-10 unchanged

**SINGLE|FORKID (0x43):**
- hashPrevouts = same as ALL (all outpoints)
- hashSequence = 32 zero bytes
- hashOutputs = SHA256d(output at input_index only)
- Fields 1, 4-7, 9-10 unchanged

**ALL|FORKID|ANYONE_CAN_PAY (0xC1):**
- hashPrevouts = 32 zero bytes
- hashSequence = 32 zero bytes
- hashOutputs = same as ALL (all outputs)
- Fields 1, 4-7, 9-10 unchanged

**NONE|FORKID|ANYONE_CAN_PAY (0xC2):**
- hashPrevouts = 32 zero bytes
- hashSequence = 32 zero bytes
- hashOutputs = 32 zero bytes

**SINGLE|FORKID|ANYONE_CAN_PAY (0xC3):**
- hashPrevouts = 32 zero bytes
- hashSequence = 32 zero bytes
- hashOutputs = SHA256d(output at input_index only)

**SINGLE edge case:**
- input_index >= outputs.length → hashOutputs = 32 zero bytes

**Existing tests:**
- Verify all 3 existing `SIGHASH_ALL|FORKID` vectors still pass (regression)

**Constant tests:**
- Verify new MASK constant = 0x1f
- Verify combined constant values (0x42, 0x43, 0xC1, 0xC2, 0xC3)

**Non-FORKID rejection:**
- Still raises ArgumentError for types without FORK_ID bit

---

## Commit

Single commit: `feat(transaction): support all SIGHASH types (NONE, SINGLE, ANYONE_CAN_PAY)`

---

## Verification

```bash
bundle exec rspec spec/bsv/transaction/transaction_spec.rb
bundle exec rubocop lib/bsv/transaction/sighash.rb lib/bsv/transaction/transaction.rb
bundle exec rake
```
