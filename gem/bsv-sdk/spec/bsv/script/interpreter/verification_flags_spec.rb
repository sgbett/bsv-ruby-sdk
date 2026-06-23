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

  describe 'OP_VERIF / OP_VERNOTIF in a non-executing branch' do
    it 'is a complete NOP post-Genesis pre-Chronicle (no cond-stack push)' do
      # scriptSig pushes false, IF takes false branch, VERIF skipped entirely,
      # ELSE flips to executing, OP_1 pushes 1, ENDIF closes. Final stack [1].
      expect(
        evaluate('OP_0', 'OP_IF OP_VERIF OP_ELSE OP_1 OP_ENDIF',
                 flags: %w[UTXO_AFTER_GENESIS])
      ).to be true
    end

    it 'VERNOTIF is a NOP post-Genesis pre-Chronicle' do
      expect(
        evaluate('OP_0', 'OP_IF OP_VERNOTIF OP_ELSE OP_1 OP_ENDIF',
                 flags: %w[UTXO_AFTER_GENESIS])
      ).to be true
    end

    it 'pre-Genesis VERIF is illegal even in a non-executing branch' do
      expect do
        evaluate('OP_0', 'OP_IF OP_VERIF OP_ELSE OP_1 OP_ENDIF',
                 flags: %w[P2SH STRICTENC])
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:disabled_opcode)
      }
    end
  end

  describe 'tx_version: parameter (Chronicle OP_VER / OP_VERIF without tx)' do
    it 'OP_VER pushes the 4-byte LE encoding of tx_version' do
      expect(
        evaluate('OP_1', 'OP_VER 01000000 OP_EQUAL',
                 flags: %w[UTXO_AFTER_GENESIS UTXO_AFTER_CHRONICLE],
                 tx_version: 1)
      ).to be true
    end

    it 'OP_VERIF compares stack data to tx_version under Chronicle' do
      # Push the 4-byte LE form of version 1, VERIF takes the matching branch.
      expect(
        evaluate('01000000', 'OP_VERIF OP_1 OP_ELSE OP_0 OP_ENDIF',
                 flags: %w[UTXO_AFTER_GENESIS UTXO_AFTER_CHRONICLE],
                 tx_version: 1)
      ).to be true
    end

    it 'OP_VER still raises MISSING_TX_CONTEXT when neither tx nor tx_version supplied' do
      expect do
        evaluate('', 'OP_VER', flags: %w[UTXO_AFTER_GENESIS UTXO_AFTER_CHRONICLE])
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:missing_tx_context)
      }
    end

    it 'OP_VER executes in relaxed mode when tx_version is supplied' do
      expect(evaluate('OP_1', 'OP_VER 01000000 OP_EQUAL', tx_version: 1)).to be true
    end

    it 'OP_VER raises :disabled_opcode when explicit non-Chronicle flags are set' do
      expect do
        evaluate('', 'OP_VER', flags: %w[UTXO_AFTER_GENESIS], tx_version: 1)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:disabled_opcode)
      }
    end
  end
end
