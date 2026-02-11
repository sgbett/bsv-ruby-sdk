# Script Interpreter — Task #21

## Context

Issue #21, last sub-task of HLR #8. Stack-based VM that executes Bitcoin scripts for local transaction validation and debugging. BSV after-genesis semantics only (no pre-genesis limits, no P2SH execution).

Reference: Go SDK `/private/tmp/go-sdk/script/interpreter/` — engine.go, thread.go, stack.go, operations.go (76 KB), number.go, errs/.

---

## Public API

```ruby
# Pure script evaluation (no transaction context — signatures always fail)
Interpreter.evaluate(unlock_script, lock_script)
# => true / raises ScriptError

# Transaction input verification (full signature checking)
Interpreter.verify(tx:, input_index:, unlock_script:, lock_script:, satoshis:)
# => true / raises ScriptError

# Convenience on Transaction
Transaction#verify_input(index)
# => true / raises ScriptError
```

---

## File Structure

```
lib/bsv/script/interpreter/
  interpreter.rb           # NEW — main class, execution loop, dispatch
  stack.rb                 # NEW — data stack + alt stack
  script_number.rb         # NEW — LE sign-magnitude numeric encoding
  error.rb                 # NEW — ScriptError + error code constants
  operations/
    data_push.rb           # NEW — OP_0, OP_1..16, OP_1NEGATE, push data
    stack_ops.rb           # NEW — DUP, DROP, SWAP, ROT, PICK, ROLL, etc.
    flow_control.rb        # NEW — IF/NOTIF/ELSE/ENDIF, VERIFY, RETURN, NOP
    bitwise.rb             # NEW — EQUAL[VERIFY], AND, OR, XOR, INVERT
    arithmetic.rb          # NEW — ADD, SUB, MUL, DIV, comparisons, etc.
    splice.rb              # NEW — CAT, SPLIT, SIZE, NUM2BIN, BIN2NUM
    crypto.rb              # NEW — hash ops, CHECKSIG, CHECKMULTISIG

lib/bsv/script.rb                          # MODIFIED — add autoloads
lib/bsv/primitives/digest.rb               # MODIFIED — add sha1
lib/bsv/transaction/transaction.rb          # MODIFIED — add verify_input, sighash subscript param

spec/bsv/script/interpreter/
  stack_spec.rb
  script_number_spec.rb
  error_spec.rb
  interpreter_spec.rb      # end-to-end integration tests
  operations/
    data_push_spec.rb
    stack_ops_spec.rb
    flow_control_spec.rb
    bitwise_spec.rb
    arithmetic_spec.rb
    splice_spec.rb
    crypto_spec.rb
```

---

## Architecture

### Interpreter class

- Constructor takes `unlock_script`, `lock_script`, optional `tx`, `input_index`, `satoshis`
- Execution loop: iterate chunks of unlock script, then chunks of lock script
- Between scripts: clear alt stack, verify conditionals balanced
- Opcode dispatch: frozen Hash mapping opcode byte → method symbol, O(1) lookup
- Conditional execution: `cond_stack` array (`:true` / `:false` / `:skip`) + `else_stack` for duplicate-ELSE detection
- `branch_executing?` checks innermost conditional
- Operation modules mixed in via `include`

### Stack class

- Internal `@items` array of binary strings
- Push/pop with type conversion: `push_bytes`, `push_int(ScriptNumber)`, `push_bool`
- Pop with interpretation: `pop_bytes`, `pop_int`, `pop_bool`
- FORTH-like ops: `dup_n`, `drop_n`, `swap_n`, `rot_n`, `over_n`, `pick_n`, `roll_n`, `nip_n`, `tuck`
- Boolean encoding: empty or all-zero bytes = false, `\x80` (negative zero) = false, anything else = true

### ScriptNumber

- Wraps Ruby Integer (already arbitrary precision — no BigInt needed unlike Go)
- `from_bytes(bytes)` — LE sign-magnitude decoding (sign bit in high bit of last byte)
- `to_bytes` — LE sign-magnitude encoding
- `require_minimal:` flag for minimal encoding enforcement
- `MAX_BYTE_LENGTH = 750_000` (after-genesis)
- Arithmetic operators: `+`, `-`, `*`, `/`, `%`, `-@`, `abs`
- Includes `Comparable`

### Error hierarchy

```ruby
class ScriptError < StandardError
  attr_reader :code  # Symbol, e.g. :eval_false, :empty_stack
end
```

Error codes: `eval_false`, `empty_stack`, `verify_failed`, `equalverify_failed`, `numequalverify_failed`, `checksigverify_failed`, `checkmultisigverify_failed`, `unbalanced_conditional`, `disabled_opcode`, `reserved_opcode`, `invalid_stack_operation`, `number_too_big`, `divide_by_zero`, `invalid_input_length`, `invalid_pubkey_count`, `invalid_sig_count`, `sig_nullfail`, `invalid_opcode`

---

## BSV-Specific Decisions

- **After-genesis only** — no script/element/stack size limits, no op count limits, OP_RETURN = early success, only one OP_ELSE per OP_IF
- **No P2SH execution** — deprecated in BSV, no BIP16 third-script phase
- **ForkID required** — all CHECKSIG ops require SIGHASH_FORKID (0x40 bit), uses existing BIP-143 sighash
- **CLTV/CSV as NOPs** — OP_CHECKLOCKTIMEVERIFY and OP_CHECKSEQUENCEVERIFY treated as OP_NOP
- **Re-enabled opcodes** — OP_MUL, OP_CAT, OP_SPLIT, OP_AND, OP_OR, OP_XOR, OP_DIV, OP_MOD, OP_INVERT, OP_LSHIFT, OP_RSHIFT, OP_NUM2BIN, OP_BIN2NUM all active
- **Disabled opcodes** — OP_2MUL, OP_2DIV raise ScriptError
- **Always-illegal** — OP_VERIF, OP_VERNOTIF fail immediately regardless of conditional state

---

## Integration Points

**Sighash** — `Transaction#sighash` already computes BIP-143 hashes. Need to add optional `subscript:` parameter for OP_CODESEPARATOR support (currently uses `input.source_locking_script` directly).

**Signature verification** — `PublicKey.from_bytes(bytes)` + `pubkey.verify(hash, Signature.from_der(der_bytes))`. Already implemented.

**Hashing** — `Digest.sha256`, `Digest.ripemd160`, `Digest.hash160`, `Digest.sha256d`. Need to add `Digest.sha1` (trivial: `OpenSSL::Digest::SHA1.digest(data)`).

**Script parsing** — Reuse `Script#chunks` to get `Chunk` objects with `opcode` and `data`.

---

## Phased Implementation (6 sub-issues)

### Phase 1: Core Engine — Stack, ScriptNumber, Errors

**New files:** `stack.rb`, `script_number.rb`, `error.rb`, `interpreter.rb` (skeleton)
**Modified:** `lib/bsv/script.rb` (autoloads)
**~400 LOC code, ~300 LOC spec**

- ScriptNumber: from_bytes/to_bytes round-tripping, arithmetic, LE sign-magnitude encoding
- Stack: all FORTH-like operations, boolean encoding, type-converting push/pop
- Error hierarchy with typed codes
- Interpreter skeleton (constructor, dispatch table — no opcodes yet)

### Phase 2: Data Push + Stack Manipulation

**New files:** `operations/data_push.rb`, `operations/stack_ops.rb`
**Modified:** `interpreter.rb` (execution loop, dispatch, includes)
**~250 LOC code, ~200 LOC spec**

- Data push: OP_0, OP_1..16, OP_1NEGATE, all PUSHDATA (chunks with data handled by dispatch)
- Stack ops: DUP, 2DUP, 3DUP, DROP, 2DROP, SWAP, 2SWAP, ROT, 2ROT, OVER, 2OVER, NIP, TUCK, PICK, ROLL, DEPTH, IFDUP, TOALTSTACK, FROMALTSTACK
- Complete execution loop: two-script sequential execution, alt stack cleared between scripts

### Phase 3: Flow Control + Equality

**New files:** `operations/flow_control.rb`, `operations/bitwise.rb`
**~200 LOC code, ~200 LOC spec**

- Flow: IF, NOTIF, ELSE, ENDIF (cond_stack + else_stack), VERIFY, RETURN (early success), NOP, NOP1-10, CLTV/CSV (as NOP)
- Reserved/always-illegal: VER, VERIF, VERNOTIF, RESERVED, RESERVED1, RESERVED2
- Bitwise: EQUAL, EQUALVERIFY, AND, OR, XOR, INVERT

### Phase 4: Arithmetic + Splice

**New files:** `operations/arithmetic.rb`, `operations/splice.rb`
**~300 LOC code, ~250 LOC spec**

- Arithmetic: 1ADD, 1SUB, NEGATE, ABS, NOT, 0NOTEQUAL, ADD, SUB, MUL, DIV, MOD, LSHIFT, RSHIFT, BOOLAND, BOOLOR, NUMEQUAL, NUMEQUALVERIFY, NUMNOTEQUAL, LESSTHAN, GREATERTHAN, LESSTHANOREQUAL, GREATERTHANOREQUAL, MIN, MAX, WITHIN
- Disabled: 2MUL, 2DIV (raise ScriptError)
- Splice: CAT, SPLIT, SIZE, NUM2BIN, BIN2NUM

### Phase 5: Crypto + Signature Verification

**New files:** `operations/crypto.rb`
**Modified:** `lib/bsv/primitives/digest.rb` (add sha1), `lib/bsv/transaction/transaction.rb` (add subscript param to sighash)
**~250 LOC code, ~200 LOC spec**

- Hashing: RIPEMD160, SHA1, SHA256, HASH160, HASH256
- CODESEPARATOR: track position, build subscript from last separator onwards
- CHECKSIG: pop pubkey + sig, extract hashtype, verify FORKID, compute sighash, verify with PublicKey#verify
- CHECKSIGVERIFY: CHECKSIG + VERIFY
- CHECKMULTISIG: pop N pubkeys + M sigs + dummy, iterate matches, handle off-by-one bug
- CHECKMULTISIGVERIFY: CHECKMULTISIG + VERIFY
- NULLFAIL: non-empty failed signature = error

### Phase 6: End-to-End Integration + Transaction#verify_input

**Modified:** `interpreter.rb` (add `verify` class method), `transaction.rb` (add `verify_input`)
**~100 LOC code, ~250 LOC spec**

- `Transaction#verify_input(index)` convenience method
- P2PKH end-to-end: create tx, sign, verify through interpreter
- P2PK, multisig verification
- Negative tests: wrong key, corrupted sig, wrong locking script
- Conditional script tests (IF branches around CHECKSIG)
- OP_RETURN scripts
- Empty/nonstandard scripts

---

## Estimated Totals

| Phase | Code | Spec | New Files | Modified |
|-------|------|------|-----------|----------|
| 1     | 400  | 300  | 7         | 1        |
| 2     | 250  | 200  | 4         | 1        |
| 3     | 200  | 200  | 4         | 0        |
| 4     | 300  | 250  | 4         | 0        |
| 5     | 250  | 200  | 2         | 2        |
| 6     | 100  | 250  | 1         | 2        |
| **Total** | **~1,500** | **~1,400** | **22** | **6** |

---

## Verification (per phase)

```bash
bundle exec rspec spec/bsv/script/interpreter/
bundle exec rubocop lib/bsv/script/interpreter/ lib/bsv/script.rb
bundle exec rake
```
