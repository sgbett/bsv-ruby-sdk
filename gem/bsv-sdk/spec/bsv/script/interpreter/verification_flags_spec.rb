# frozen_string_literal: true

require 'spec_helper'

# Cross-cutting tests for the explicit verification-flag plumbing on
# +Interpreter.evaluate+. Flag-specific behaviour (SIGPUSHONLY, CLEANSTACK,
# Chronicle gating) lives in its own +describe+ block within this file.
RSpec.describe BSV::Script::Interpreter do
  def evaluate(unlock_asm, lock_asm, **opts)
    unlock = unlock_asm.empty? ? BSV::Script::Script.new : BSV::Script::Script.from_asm(unlock_asm)
    lock = lock_asm.empty? ? BSV::Script::Script.new : BSV::Script::Script.from_asm(lock_asm)
    described_class.evaluate(unlock, lock, **opts)
  end

  describe 'SIGPUSHONLY flag' do
    it 'rejects an unlock script containing OP_RETURN' do
      expect do
        evaluate('OP_RETURN', 'OP_1', flags: %w[SIGPUSHONLY])
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:sig_pushonly)
      }
    end

    it 'rejects an unlock script containing non-push opcodes such as OP_DUP' do
      expect do
        evaluate('OP_1 OP_DUP', 'OP_1', flags: %w[SIGPUSHONLY])
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:sig_pushonly)
      }
    end

    it 'accepts a push-only unlock script under SIGPUSHONLY' do
      # OP_1 is opcode 0x51, below OP_16 (0x60) — counted as push-only.
      expect(evaluate('OP_1', 'OP_1', flags: %w[SIGPUSHONLY])).to be true
    end

    it 'does not enforce SIGPUSHONLY when the flag is absent (explicit non-Chronicle flags)' do
      # No SIGPUSHONLY flag → OP_RETURN in unlock allowed; OP_RETURN ends execution
      # with the unlock-pushed truthy value left on the stack.
      expect(evaluate('OP_1 OP_RETURN', 'OP_1', flags: %w[UTXO_AFTER_GENESIS])).to be true
    end

    it 'does not enforce SIGPUSHONLY in relaxed (no-flags) mode' do
      expect(evaluate('OP_1 OP_RETURN', 'OP_1')).to be true
    end
  end

  describe 'CLEANSTACK flag' do
    it 'rejects scripts that leave more than one item on the stack' do
      # OP_1 OP_1 leaves [1, 1] — two items, both truthy.
      expect do
        evaluate('OP_1', 'OP_1', flags: %w[CLEANSTACK])
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:clean_stack)
      }
    end

    it 'accepts a single-item truthy stack under CLEANSTACK' do
      expect(evaluate('OP_1', '', flags: %w[CLEANSTACK])).to be true
    end

    it 'still raises EVAL_FALSE before the clean-stack check applies to a falsy single item' do
      # OP_0 leaves a single empty-bytes item — clean (length == 1) but falsy.
      expect do
        evaluate('OP_0', '', flags: %w[CLEANSTACK])
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:eval_false)
      }
    end

    it 'does not enforce CLEANSTACK when the flag is absent (explicit non-Chronicle flags)' do
      expect(evaluate('OP_1', 'OP_1', flags: %w[UTXO_AFTER_GENESIS])).to be true
    end

    it 'does not enforce CLEANSTACK in relaxed (no-flags) mode' do
      expect(evaluate('OP_1', 'OP_1')).to be true
    end
  end

  describe 'Chronicle-only opcodes' do
    it 'OP_2MUL raises :disabled_opcode with explicit non-Chronicle flags' do
      expect do
        evaluate('OP_1', 'OP_2MUL', flags: %w[UTXO_AFTER_GENESIS])
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:disabled_opcode)
      }
    end

    it 'OP_2DIV raises :disabled_opcode with explicit non-Chronicle flags' do
      expect do
        evaluate('OP_2', 'OP_2DIV', flags: %w[UTXO_AFTER_GENESIS])
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:disabled_opcode)
      }
    end

    it 'OP_2MUL executes with UTXO_AFTER_CHRONICLE' do
      expect(
        evaluate('OP_1', 'OP_2MUL OP_2 OP_EQUAL', flags: %w[UTXO_AFTER_GENESIS UTXO_AFTER_CHRONICLE])
      ).to be true
    end

    it 'OP_2DIV executes with UTXO_AFTER_CHRONICLE' do
      expect(
        evaluate('OP_2', 'OP_2DIV OP_1 OP_EQUAL', flags: %w[UTXO_AFTER_GENESIS UTXO_AFTER_CHRONICLE])
      ).to be true
    end

    it 'OP_2MUL executes in relaxed (no-flags) mode (Chronicle default)' do
      expect(evaluate('OP_1', 'OP_2MUL OP_2 OP_EQUAL')).to be true
    end
  end
end
