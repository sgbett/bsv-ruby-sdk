# frozen_string_literal: true

require 'spec_helper'

# Specs for A6 interpreter hardening findings (HLR #318).
# Covers: F7.18 stack memory limit, F7.11 minimal encoding default,
# F7.9 NULLFAIL no-tx path, F7.8 CHECKMULTISIG key cap removal,
# F7.10 hybrid pubkey rejection, F7.19 conditional depth cap,
# F7.1/F7.2 Chronicle opcode fail-safe.

RSpec.describe 'A6 Interpreter Hardening' do
  let(:empty_script) { BSV::Script::Script.new }

  def evaluate(unlock_asm, lock_asm)
    unlock = unlock_asm.empty? ? BSV::Script::Script.new : BSV::Script::Script.from_asm(unlock_asm)
    lock = lock_asm.empty? ? BSV::Script::Script.new : BSV::Script::Script.from_asm(lock_asm)
    BSV::Script::Interpreter.evaluate(unlock, lock)
  end

  def build_interpreter
    BSV::Script::Interpreter.send(:new, unlock_script: empty_script, lock_script: empty_script)
  end

  # ---------------------------------------------------------------------------
  # F7.18 — Stack memory limit (32 MB)
  # ---------------------------------------------------------------------------

  describe 'F7.18: Stack memory limit' do
    let(:stack) { BSV::Script::Stack.new }

    it 'raises :stack_memory_exceeded when a single push would exceed 32 MB' do
      large = "\x00".b * (BSV::Script::Stack::MAX_MEMORY_BYTES + 1)
      expect do
        stack.push_bytes(large)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:stack_memory_exceeded)
      }
    end

    it 'does not raise for a push that exactly reaches the limit' do
      exact = "\x00".b * BSV::Script::Stack::MAX_MEMORY_BYTES
      expect { stack.push_bytes(exact) }.not_to raise_error
    end

    it 'accumulates usage across multiple pushes and raises when combined total exceeds limit' do
      # Push 16 MB twice — second push should tip over the 32 MB limit
      chunk = "\x00".b * (16 * 1024 * 1024)
      stack.push_bytes(chunk)
      stack.push_bytes(chunk)

      small = "\x01".b
      expect do
        stack.push_bytes(small)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:stack_memory_exceeded)
      }
    end

    it 'decrements usage on pop, allowing further pushes afterwards' do
      chunk = "\x00".b * (16 * 1024 * 1024)
      stack.push_bytes(chunk)
      stack.push_bytes(chunk)
      stack.pop_bytes # free 16 MB

      expect { stack.push_bytes("\x01".b) }.not_to raise_error
    end

    it 'resets usage on #clear' do
      stack.push_bytes("\x00".b * (16 * 1024 * 1024))
      stack.clear
      expect { stack.push_bytes("\x00".b * (16 * 1024 * 1024)) }.not_to raise_error
    end

    it 'enforces the limit in dup_n (OP_DUP family)' do
      # Fill to ~31 MB then try to dup
      chunk = "\x00".b * (31 * 1024 * 1024)
      stack.push_bytes(chunk)

      # Dup would add another 31 MB, exceeding 32 MB
      expect do
        stack.dup_n(1)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:stack_memory_exceeded)
      }
    end

    it 'enforces the limit in over_n (OP_OVER family)' do
      chunk = "\x00".b * (16 * 1024 * 1024)
      stack.push_bytes(chunk)
      stack.push_bytes(chunk)

      expect do
        stack.over_n(1)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:stack_memory_exceeded)
      }
    end

    it 'enforces the limit in pick_n (OP_PICK)' do
      chunk = "\x00".b * (16 * 1024 * 1024)
      stack.push_bytes(chunk)
      stack.push_bytes(chunk)

      expect do
        stack.pick_n(1)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:stack_memory_exceeded)
      }
    end

    it 'enforces the limit in tuck (OP_TUCK)' do
      chunk = "\x00".b * (16 * 1024 * 1024)
      stack.push_bytes(chunk)
      stack.push_bytes(chunk)

      expect do
        stack.tuck
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:stack_memory_exceeded)
      }
    end

    it 'MAX_MEMORY_BYTES is 32 MB' do
      expect(BSV::Script::Stack::MAX_MEMORY_BYTES).to eq(32 * 1024 * 1024)
    end
  end

  # ---------------------------------------------------------------------------
  # F7.11 — Minimal encoding default
  # ---------------------------------------------------------------------------

  describe 'F7.11: Minimal encoding default' do
    let(:stack) { BSV::Script::Stack.new }

    it 'raises :minimal_data for non-minimal encoding by default (pop_int)' do
      # "\x00\x00" is a non-minimal encoding of zero
      stack.push_bytes("\x00\x00".b)
      expect do
        stack.pop_int
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:minimal_data)
      }
    end

    it 'accepts non-minimal encoding when require_minimal: false is explicit' do
      stack.push_bytes("\x00\x00".b)
      expect { stack.pop_int(require_minimal: false) }.not_to raise_error
    end

    it 'raises :minimal_data for non-minimal encoding by default (peek_int)' do
      stack.push_bytes("\x00\x00".b)
      expect do
        stack.peek_int
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:minimal_data)
      }
    end

    it 'accepts well-formed minimal encodings normally' do
      stack.push_bytes("\x01".b) # minimal encoding of 1
      expect(stack.pop_int.value).to eq(1)
    end

    it 'accepts empty bytes as zero (minimal)' do
      stack.push_bytes(''.b)
      expect(stack.pop_int.value).to eq(0)
    end
  end

  # ---------------------------------------------------------------------------
  # F7.9 — NULLFAIL in no-tx path
  # ---------------------------------------------------------------------------

  describe 'F7.9: NULLFAIL in no-tx path' do
    it 'pushes false (not raises) when CHECKSIG has non-empty sig and no tx context' do
      interp = build_interpreter

      # Build a plausible-looking (but unverifiable) sig + valid compressed pubkey
      priv = BSV::Primitives::PrivateKey.generate
      pub = priv.public_key
      hash = "\x00".b * 32
      sig = priv.sign(hash)
      sig_bytes = sig.to_der + [BSV::Transaction::Sighash::ALL_FORK_ID].pack('C')

      interp.dstack.push_bytes(sig_bytes)
      interp.dstack.push_bytes(pub.compressed)
      expect { interp.send(:op_checksig) }.not_to raise_error
      expect(interp.dstack.pop_bool).to be false
    end

    it 'raises :sig_nullfail when CHECKSIG fails with a tx context present' do
      # Use a P2PK transaction with the wrong signing key — the sig is well-formed
      # DER but will not verify against the lock script's public key.
      priv = BSV::Primitives::PrivateKey.generate
      pub = priv.public_key
      lock_script = BSV::Script::Script.p2pk_lock(pub.compressed)

      tx = BSV::Transaction::Transaction.new
      input = BSV::Transaction::TransactionInput.new(
        prev_tx_id: "\x00" * 32,
        prev_tx_out_index: 0
      )
      input.source_locking_script = lock_script
      input.source_satoshis = 50_000
      tx.add_input(input)
      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: 49_000,
                      locking_script: lock_script
                    ))

      # Sign with the wrong key — valid DER sig, won't verify against pub
      wrong_priv = BSV::Primitives::PrivateKey.generate
      hash = tx.sighash(0)
      wrong_sig = wrong_priv.sign(hash).to_der + [BSV::Transaction::Sighash::ALL_FORK_ID].pack('C')
      unlock_script = BSV::Script::Script.p2pk_unlock(wrong_sig)

      expect do
        BSV::Script::Interpreter.verify(
          tx: tx,
          input_index: 0,
          unlock_script: unlock_script,
          lock_script: lock_script,
          satoshis: 50_000
        )
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:sig_nullfail)
      }
    end

    it 'pushes false (not raises) when CHECKMULTISIG has non-empty sigs and no tx' do
      interp = build_interpreter

      priv = BSV::Primitives::PrivateKey.generate
      pub = priv.public_key
      hash = "\x00".b * 32
      sig = priv.sign(hash)
      sig_bytes = sig.to_der + [BSV::Transaction::Sighash::ALL_FORK_ID].pack('C')

      # Stack layout for OP_CHECKMULTISIG: dummy | sigs | num_sigs | keys | num_keys
      interp.dstack.push_bytes(''.b)             # dummy
      interp.dstack.push_bytes(sig_bytes)        # sig
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(1)) # num_sigs
      interp.dstack.push_bytes(pub.compressed) # pubkey
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(1)) # num_keys

      expect { interp.send(:op_checkmultisig) }.not_to raise_error
      expect(interp.dstack.pop_bool).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # F7.8 — CHECKMULTISIG key cap removal
  # ---------------------------------------------------------------------------

  describe 'F7.8: CHECKMULTISIG key cap removed' do
    it 'accepts more than 20 keys without raising' do
      interp = build_interpreter

      # Build 21 key pairs and sign with all of them
      keys = Array.new(21) { BSV::Primitives::PrivateKey.generate }
      pubkeys = keys.map { |k| k.public_key.compressed }

      # Push dummy, 0 sigs, num_sigs=0, all pubkeys, num_keys=21
      interp.dstack.push_bytes(''.b)
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(0))
      pubkeys.each { |pk| interp.dstack.push_bytes(pk) }
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(21))

      expect { interp.send(:op_checkmultisig) }.not_to raise_error
    end

    it 'still rejects a negative key count' do
      interp = build_interpreter
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(-1))

      expect do
        interp.send(:op_checkmultisig)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_pubkey_count)
      }
    end
  end

  # ---------------------------------------------------------------------------
  # F7.10 — Hybrid pubkey rejection
  # ---------------------------------------------------------------------------

  describe 'F7.10: Hybrid pubkey prefix rejection' do
    it 'rejects a pubkey with hybrid prefix 0x06 (65 bytes)' do
      interp = build_interpreter

      priv = BSV::Primitives::PrivateKey.generate
      pub = priv.public_key
      uncompressed = pub.uncompressed
      # Hybrid prefix: replace 0x04 with 0x06
      hybrid_key = "\x06".b + uncompressed.byteslice(1..)

      expect do
        interp.send(:validate_pubkey_encoding!, hybrid_key)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:pubkey_type)
      }
    end

    it 'rejects a pubkey with hybrid prefix 0x07 (65 bytes)' do
      interp = build_interpreter

      priv = BSV::Primitives::PrivateKey.generate
      pub = priv.public_key
      uncompressed = pub.uncompressed
      hybrid_key = "\x07".b + uncompressed.byteslice(1..)

      expect do
        interp.send(:validate_pubkey_encoding!, hybrid_key)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:pubkey_type)
      }
    end

    it 'accepts compressed keys (0x02 / 0x03)' do
      interp = build_interpreter
      priv = BSV::Primitives::PrivateKey.generate
      pub = priv.public_key
      expect { interp.send(:validate_pubkey_encoding!, pub.compressed) }.not_to raise_error
    end

    it 'accepts uncompressed keys (0x04)' do
      interp = build_interpreter
      priv = BSV::Primitives::PrivateKey.generate
      pub = priv.public_key
      expect { interp.send(:validate_pubkey_encoding!, pub.uncompressed) }.not_to raise_error
    end
  end

  # ---------------------------------------------------------------------------
  # F7.19 — Conditional depth cap at 256
  # ---------------------------------------------------------------------------

  describe 'F7.19: Conditional depth cap' do
    it 'raises :unbalanced_conditional at depth 257' do
      # Build a script with 257 nested OP_IF blocks
      # Each OP_IF needs OP_1 (condition) on the stack — we build a preimage
      # in the unlock script, then a deeply nested IF in the lock script
      depth = BSV::Script::Interpreter::MAX_CONDITIONAL_DEPTH + 1

      # Construct a raw script binary manually
      opcodes = []
      depth.times do
        opcodes << BSV::Script::Opcodes::OP_1    # condition
        opcodes << BSV::Script::Opcodes::OP_IF
      end
      opcodes << BSV::Script::Opcodes::OP_1      # leaves something on stack
      depth.times { opcodes << BSV::Script::Opcodes::OP_ENDIF }

      lock = BSV::Script::Script.from_binary(opcodes.pack('C*'))

      expect do
        BSV::Script::Interpreter.evaluate(empty_script, lock)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:unbalanced_conditional)
      }
    end

    it 'allows nesting up to exactly 256 levels' do
      depth = BSV::Script::Interpreter::MAX_CONDITIONAL_DEPTH

      opcodes = []
      depth.times do
        opcodes << BSV::Script::Opcodes::OP_1
        opcodes << BSV::Script::Opcodes::OP_IF
      end
      opcodes << BSV::Script::Opcodes::OP_1
      depth.times { opcodes << BSV::Script::Opcodes::OP_ENDIF }

      lock = BSV::Script::Script.from_binary(opcodes.pack('C*'))
      expect { BSV::Script::Interpreter.evaluate(empty_script, lock) }.not_to raise_error
    end
  end

  # ---------------------------------------------------------------------------
  # F7.1/F7.2 — Chronicle opcode constants
  # All Chronicle opcodes (OP_SUBSTR, OP_LEFT, OP_RIGHT, OP_LSHIFTNUM,
  # OP_RSHIFTNUM, OP_VER, OP_VERIF, OP_VERNOTIF) are now implemented.
  # ---------------------------------------------------------------------------

  describe 'F7.1/F7.2: Chronicle opcode constants' do
    it 'Chronicle opcode constants are defined in BSV::Script::Opcodes' do
      expect(BSV::Script::Opcodes::OP_SUBSTR).to eq(0xb3)
      expect(BSV::Script::Opcodes::OP_LEFT).to eq(0xb4)
      expect(BSV::Script::Opcodes::OP_RIGHT).to eq(0xb5)
      expect(BSV::Script::Opcodes::OP_LSHIFTNUM).to eq(0xb6)
      expect(BSV::Script::Opcodes::OP_RSHIFTNUM).to eq(0xb7)
    end

    it 'NOP aliases still map to the same byte values' do
      expect(BSV::Script::Opcodes::OP_NOP4).to eq(BSV::Script::Opcodes::OP_SUBSTR)
      expect(BSV::Script::Opcodes::OP_NOP5).to eq(BSV::Script::Opcodes::OP_LEFT)
      expect(BSV::Script::Opcodes::OP_NOP6).to eq(BSV::Script::Opcodes::OP_RIGHT)
      expect(BSV::Script::Opcodes::OP_NOP7).to eq(BSV::Script::Opcodes::OP_LSHIFTNUM)
      expect(BSV::Script::Opcodes::OP_NOP8).to eq(BSV::Script::Opcodes::OP_RSHIFTNUM)
    end
  end
end
