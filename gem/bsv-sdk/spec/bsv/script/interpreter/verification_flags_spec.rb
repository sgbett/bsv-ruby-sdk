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
end
