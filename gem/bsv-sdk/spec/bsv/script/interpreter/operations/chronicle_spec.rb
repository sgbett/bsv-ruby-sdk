# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Chronicle opcodes' do
  def evaluate(unlock_asm, lock_asm)
    unlock = unlock_asm.empty? ? BSV::Script::Script.new : BSV::Script::Script.from_asm(unlock_asm)
    lock = lock_asm.empty? ? BSV::Script::Script.new : BSV::Script::Script.from_asm(lock_asm)
    BSV::Script::Interpreter.evaluate(unlock, lock)
  end

  # Build a minimal transaction wired for Interpreter.verify.
  # OP_VER / OP_VERIF / OP_VERNOTIF scripts need no signatures — the transaction
  # just needs inputs and outputs to satisfy the Transaction structure.
  def build_ver_tx(version:)
    tx = BSV::Transaction::Transaction.new(version: version)
    input = BSV::Transaction::TransactionInput.new(
      prev_tx_id: "\x00" * 32,
      prev_tx_out_index: 0
    )
    dummy_lock = BSV::Script::Script.new
    input.source_locking_script = dummy_lock
    input.source_satoshis = 1_000
    tx.add_input(input)
    tx.add_output(BSV::Transaction::TransactionOutput.new(
                    satoshis: 900,
                    locking_script: BSV::Script::Script.new
                  ))
    tx
  end

  def verify_ver(lock_asm, version:)
    tx = build_ver_tx(version: version)
    lock = BSV::Script::Script.from_asm(lock_asm)
    unlock = BSV::Script::Script.new
    BSV::Script::Interpreter.verify(
      tx: tx,
      input_index: 0,
      unlock_script: unlock,
      lock_script: lock,
      satoshis: 1_000
    )
  end

  # OP_2MUL (0x8d) — multiply top of stack by 2
  describe 'OP_2MUL' do
    it 'OP_1 OP_2MUL pushes 2' do
      expect(evaluate('', 'OP_1 OP_2MUL OP_2 OP_EQUAL')).to be true
    end

    it 'OP_0 OP_2MUL pushes 0' do
      expect(evaluate('', 'OP_0 OP_2MUL OP_0 OP_EQUAL')).to be true
    end

    it 'OP_8 OP_2MUL OP_16 OP_EQUAL succeeds' do
      expect(evaluate('', 'OP_8 OP_2MUL OP_16 OP_EQUAL')).to be true
    end

    it 'OP_1NEGATE OP_2MUL pushes -2' do
      expect(evaluate('', 'OP_1NEGATE OP_2MUL OP_2 OP_NEGATE OP_EQUAL')).to be true
    end

    it 'raises invalid_stack_operation on empty stack' do
      expect do
        evaluate('', 'OP_2MUL')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_stack_operation)
      }
    end
  end

  # OP_2DIV (0x8e) — integer-divide top of stack by 2, truncating toward zero
  describe 'OP_2DIV' do
    it 'OP_2 OP_2DIV pushes 1' do
      expect(evaluate('', 'OP_2 OP_2DIV OP_1 OP_EQUAL')).to be true
    end

    it 'OP_16 OP_2DIV OP_8 OP_EQUAL succeeds' do
      expect(evaluate('', 'OP_16 OP_2DIV OP_8 OP_EQUAL')).to be true
    end

    it 'OP_1 OP_2DIV pushes 0 (truncation toward zero)' do
      expect(evaluate('', 'OP_1 OP_2DIV OP_0 OP_EQUAL')).to be true
    end

    it 'OP_0 OP_2DIV pushes 0' do
      expect(evaluate('', 'OP_0 OP_2DIV OP_0 OP_EQUAL')).to be true
    end

    it 'raises invalid_stack_operation on empty stack' do
      expect do
        evaluate('', 'OP_2DIV')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_stack_operation)
      }
    end
  end

  # OP_SUBSTR (0xb3) — extract substring by offset and length
  # Stack: [... data offset len] -> [... data[offset, len]]
  describe 'OP_SUBSTR' do
    # "HelloWorld" = 48656c6c6f576f726c64
    # "oWorl"      = 6f576f726c
    it 'extracts middle substring (offset=4, len=5)' do
      expect(evaluate('', '48656c6c6f576f726c64 OP_4 OP_5 OP_SUBSTR 6f576f726c OP_EQUAL')).to be true
    end

    # "ABC" = 414243, offset=0, len=3 -> full string
    it 'extracts full string (offset=0, len=length)' do
      expect(evaluate('', '414243 OP_0 OP_3 OP_SUBSTR 414243 OP_EQUAL')).to be true
    end

    # "Hello" = 48656c6c6f, offset=0, len=1 -> "H" = 48
    it 'extracts first character (offset=0, len=1)' do
      expect(evaluate('', '48656c6c6f OP_0 OP_1 OP_SUBSTR 48 OP_EQUAL')).to be true
    end

    # "Hi" = 4869, offset=5 (>= size=2) -> error
    it 'raises invalid_input_length when offset is out of range' do
      expect do
        evaluate('', '4869 OP_5 OP_1 OP_SUBSTR')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_input_length)
      }
    end

    # "Hi" = 4869, offset=1, len=5 (> size-offset = 1) -> error
    it 'raises invalid_input_length when length exceeds available bytes' do
      expect do
        evaluate('', '4869 OP_1 OP_5 OP_SUBSTR')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_input_length)
      }
    end

    # Empty data with offset=0 fails because offset < bytesize (0 < 0) is false.
    # This matches Go SDK semantics.
    it 'raises invalid_input_length on empty data even with offset=0 len=0' do
      expect do
        evaluate('', 'OP_0 OP_0 OP_0 OP_SUBSTR')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_input_length)
      }
    end

    it 'raises invalid_stack_operation on empty stack' do
      expect do
        evaluate('', 'OP_SUBSTR')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_stack_operation)
      }
    end
  end

  # OP_LEFT (0xb4) — extract leftmost N bytes
  # Stack: [... data len] -> [... data[0, len]]
  describe 'OP_LEFT' do
    # "HelloWorld" = 48656c6c6f576f726c64, left 5 -> "Hello" = 48656c6c6f
    it 'extracts left N bytes' do
      expect(evaluate('', '48656c6c6f576f726c64 OP_5 OP_LEFT 48656c6c6f OP_EQUAL')).to be true
    end

    # "Hello" = 48656c6c6f, left 0 -> empty
    it 'returns empty bytes when len is 0' do
      expect(evaluate('', '48656c6c6f OP_0 OP_LEFT OP_0 OP_EQUAL')).to be true
    end

    # "Hello" = 48656c6c6f, left 5 -> full string
    it 'returns full string when len equals length' do
      expect(evaluate('', '48656c6c6f OP_5 OP_LEFT 48656c6c6f OP_EQUAL')).to be true
    end

    # "Hi" = 4869, len=5 (> size=2) -> error
    it 'raises invalid_input_length when length exceeds data size' do
      expect do
        evaluate('', '4869 OP_5 OP_LEFT')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_input_length)
      }
    end

    it 'raises invalid_stack_operation on empty stack' do
      expect do
        evaluate('', 'OP_LEFT')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_stack_operation)
      }
    end
  end

  # OP_RIGHT (0xb5) — extract rightmost N bytes
  # Stack: [... data len] -> [... data[size-len, len]]
  describe 'OP_RIGHT' do
    # "HelloWorld" = 48656c6c6f576f726c64, right 5 -> "World" = 576f726c64
    it 'extracts right N bytes' do
      expect(evaluate('', '48656c6c6f576f726c64 OP_5 OP_RIGHT 576f726c64 OP_EQUAL')).to be true
    end

    # "Hello" = 48656c6c6f, right 1 -> "o" = 6f
    it 'extracts last byte' do
      expect(evaluate('', '48656c6c6f OP_1 OP_RIGHT 6f OP_EQUAL')).to be true
    end

    # "Hello" = 48656c6c6f, right 5 -> full string
    it 'returns full string when len equals length' do
      expect(evaluate('', '48656c6c6f OP_5 OP_RIGHT 48656c6c6f OP_EQUAL')).to be true
    end

    # "Hi" = 4869, len=5 (> size=2) -> error
    it 'raises invalid_input_length when length exceeds data size' do
      expect do
        evaluate('', '4869 OP_5 OP_RIGHT')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_input_length)
      }
    end

    it 'raises invalid_stack_operation on empty stack' do
      expect do
        evaluate('', 'OP_RIGHT')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_stack_operation)
      }
    end

    # Composition: LEFT(5) + RIGHT(5) with CAT reconstructs original
    it 'left and right halves concatenate to reconstruct original' do
      # "HelloWorld" (10 bytes): LEFT(5) = "Hello", RIGHT(5) = "World", CAT = "HelloWorld"
      script = '48656c6c6f576f726c64 OP_5 OP_LEFT 48656c6c6f576f726c64 OP_5 OP_RIGHT OP_CAT 48656c6c6f576f726c64 OP_EQUAL'
      expect(evaluate('', script)).to be true
    end
  end

  # OP_VER (0x62) — push 4-byte little-endian transaction version onto the stack
  describe 'OP_VER' do
    it 'pushes correct 4-byte LE bytes for version 1' do
      # 01000000 is the hex push of \x01\x00\x00\x00
      expect(verify_ver('OP_VER 01000000 OP_EQUAL', version: 1)).to be true
    end

    it 'pushes correct 4-byte LE bytes for version 2' do
      expect(verify_ver('OP_VER 02000000 OP_EQUAL', version: 2)).to be true
    end

    it 'always pushes exactly 4 bytes (OP_SIZE = 4)' do
      expect(verify_ver('OP_VER OP_SIZE OP_4 OP_EQUALVERIFY 01000000 OP_EQUAL', version: 1)).to be true
    end

    it 'version 0 pushes 00000000' do
      expect(verify_ver('OP_VER 00000000 OP_EQUAL', version: 0)).to be true
    end

    it 'version 256 pushes 00010000' do
      expect(verify_ver('OP_VER 00010000 OP_EQUAL', version: 256)).to be true
    end

    it 'OP_VER OP_DROP OP_1 succeeds (version is droppable)' do
      expect(verify_ver('OP_VER OP_DROP OP_1', version: 1)).to be true
    end

    it 'raises :missing_tx_context when called without transaction context' do
      script = BSV::Script::Script.from_asm('OP_VER')
      expect do
        BSV::Script::Interpreter.evaluate(BSV::Script::Script.new, script)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:missing_tx_context)
      }
    end
  end

  # OP_VERIF (0x65) — version-conditional branch (like OP_IF but compares tx version)
  # OP_VERNOTIF (0x66) — inverse version-conditional branch (like OP_NOTIF but compares tx version)
  #
  # These tests use Interpreter.verify with explicit tx version where needed.
  # The build_ver_tx / verify_ver helpers are defined at the top-level describe scope.
  describe 'OP_VERIF' do
    it 'matching version (v1) executes true branch' do
      # [01000000] VERIF 1 ELSE 0 ENDIF — version 1 matches → true branch → result is 1
      expect(verify_ver('01000000 OP_VERIF OP_1 OP_ELSE OP_0 OP_ENDIF', version: 1)).to be true
    end

    it 'non-matching version (v1 tx, push v2) executes else branch' do
      # [02000000] VERIF 0 ELSE 1 ENDIF — v2 data ≠ v1 tx → else → result is 1
      expect(verify_ver('02000000 OP_VERIF OP_0 OP_ELSE OP_1 OP_ENDIF', version: 1)).to be true
    end

    it 'OP_0 (0 bytes) never matches — executes else branch' do
      # OP_0 pushes empty bytes (0 bytes), never equal to the 4-byte version
      expect(verify_ver('OP_0 OP_VERIF OP_0 OP_ELSE OP_1 OP_ENDIF', version: 1)).to be true
    end

    it 'single byte [01] never matches 4-byte version — executes else branch' do
      expect(verify_ver('01 OP_VERIF OP_0 OP_ELSE OP_1 OP_ENDIF', version: 1)).to be true
    end

    it 'raises :invalid_stack_operation on empty stack' do
      expect do
        verify_ver('OP_VERIF OP_1 OP_ELSE OP_0 OP_ENDIF', version: 1)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_stack_operation)
      }
    end

    it 'VERIF in non-executing branch tracks nesting depth without popping stack' do
      # OP_0 IF VERIF ENDIF 1 — outer IF is false; VERIF is tracked for nesting
      # (pushes :false to cond_stack) without touching the data stack.
      # After ENDIF × 2, stack has 1 from OP_1 push.
      expect(verify_ver('OP_0 OP_IF OP_VERIF OP_ENDIF OP_ENDIF OP_1', version: 1)).to be true
    end

    it 'OP_VER pushes version, VERIF matches it (round-trip)' do
      # VER pushes [01000000]; VERIF pops and compares → match → true branch
      expect(verify_ver('OP_VER OP_VERIF OP_1 OP_ELSE OP_0 OP_ENDIF', version: 1)).to be true
    end

    it 'nested VERIF inside outer VERIF — both match' do
      # [01000000] VERIF [01000000] VERIF 1 ELSE 0 ENDIF ELSE 0 ENDIF
      script = '01000000 OP_VERIF 01000000 OP_VERIF OP_1 OP_ELSE OP_0 OP_ENDIF OP_ELSE OP_0 OP_ENDIF'
      expect(verify_ver(script, version: 1)).to be true
    end

    it 'without tx context always takes else branch (not an error)' do
      # No tx → tx_version_matches? returns false → else branch → result is 1
      unlock = BSV::Script::Script.new
      lock = BSV::Script::Script.from_asm('01000000 OP_VERIF OP_0 OP_ELSE OP_1 OP_ENDIF')
      expect(BSV::Script::Interpreter.evaluate(unlock, lock)).to be true
    end
  end

  describe 'OP_VERNOTIF' do
    it 'non-matching version executes true branch (inverse of VERIF)' do
      # [01FF0000] ≠ v1 → VERNOTIF true branch → result is 1
      expect(verify_ver('01FF0000 OP_VERNOTIF OP_1 OP_ELSE OP_0 OP_ENDIF', version: 1)).to be true
    end

    it 'matching version executes else branch (inverse of VERIF)' do
      # [01000000] = v1 → VERNOTIF false → else branch → result is 1
      expect(verify_ver('01000000 OP_VERNOTIF OP_0 OP_ELSE OP_1 OP_ENDIF', version: 1)).to be true
    end

    it 'OP_0 (0 bytes) never matches — VERNOTIF executes true branch' do
      # 0 bytes ≠ 4-byte version → no match → VERNOTIF true → result is 1
      expect(verify_ver('OP_0 OP_VERNOTIF OP_1 OP_ELSE OP_0 OP_ENDIF', version: 1)).to be true
    end

    it 'raises :invalid_stack_operation on empty stack' do
      expect do
        verify_ver('OP_VERNOTIF OP_1 OP_ELSE OP_0 OP_ENDIF', version: 1)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_stack_operation)
      }
    end

    it 'VERNOTIF in non-executing branch tracks nesting depth without popping stack' do
      expect(verify_ver('OP_0 OP_IF OP_VERNOTIF OP_ENDIF OP_ENDIF OP_1', version: 1)).to be true
    end

    it 'without tx context always takes true branch (not an error)' do
      # No tx → tx_version_matches? returns false → VERNOTIF true branch → result is 1
      unlock = BSV::Script::Script.new
      lock = BSV::Script::Script.from_asm('01000000 OP_VERNOTIF OP_1 OP_ELSE OP_0 OP_ENDIF')
      expect(BSV::Script::Interpreter.evaluate(unlock, lock)).to be true
    end
  end

  # OP_LSHIFTNUM (0xb6) — numeric left shift
  describe 'OP_LSHIFTNUM' do
    it '1 << 2 = 4' do
      expect(evaluate('', 'OP_1 OP_2 OP_LSHIFTNUM OP_4 OP_EQUAL')).to be true
    end

    it '1 << 0 = 1 (identity)' do
      expect(evaluate('', 'OP_1 OP_0 OP_LSHIFTNUM OP_1 OP_EQUAL')).to be true
    end

    it '7 << 0 = 7 (identity)' do
      expect(evaluate('', 'OP_7 OP_0 OP_LSHIFTNUM OP_7 OP_EQUAL')).to be true
    end

    it '1 << 8 = 256' do
      # 256 in script number encoding: [0x00, 0x01] (little-endian, sign-magnitude)
      expect(evaluate('', 'OP_1 OP_8 OP_LSHIFTNUM 0001 OP_EQUAL')).to be true
    end

    it 'raises invalid_input_length for negative shift' do
      expect do
        evaluate('', 'OP_1 OP_1NEGATE OP_LSHIFTNUM')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_input_length)
      }
    end

    it 'raises invalid_stack_operation on empty stack' do
      expect do
        evaluate('', 'OP_LSHIFTNUM')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_stack_operation)
      }
    end
  end

  # OP_RSHIFTNUM (0xb7) — numeric arithmetic right shift
  describe 'OP_RSHIFTNUM' do
    it '16 >> 2 = 4' do
      expect(evaluate('', 'OP_16 OP_2 OP_RSHIFTNUM OP_4 OP_EQUAL')).to be true
    end

    it '4 >> 2 = 1' do
      expect(evaluate('', 'OP_4 OP_2 OP_RSHIFTNUM OP_1 OP_EQUAL')).to be true
    end

    it '1 >> 8 = 0 (shift to zero)' do
      expect(evaluate('', 'OP_1 OP_8 OP_RSHIFTNUM OP_0 OP_EQUAL')).to be true
    end

    it '-16 >> 2 = -4 (sign preserved)' do
      # -16 pushed as OP_16 OP_NEGATE; -4 as OP_4 OP_NEGATE
      expect(evaluate('', 'OP_16 OP_NEGATE OP_2 OP_RSHIFTNUM OP_4 OP_NEGATE OP_EQUAL')).to be true
    end

    it '-1 >> 1 = 0 (NOT -1 — differs from Ruby native >>)' do
      expect(evaluate('', 'OP_1NEGATE OP_1 OP_RSHIFTNUM OP_0 OP_EQUAL')).to be true
    end

    it 'raises invalid_input_length for negative shift' do
      expect do
        evaluate('', 'OP_1 OP_1NEGATE OP_RSHIFTNUM')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_input_length)
      }
    end

    it 'raises invalid_stack_operation on empty stack' do
      expect do
        evaluate('', 'OP_RSHIFTNUM')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_stack_operation)
      }
    end
  end
end
# rubocop:enable RSpec/DescribeClass
