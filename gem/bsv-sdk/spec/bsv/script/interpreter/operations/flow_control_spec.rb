# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Script::Interpreter do
  def evaluate(unlock_asm, lock_asm)
    unlock = unlock_asm.empty? ? BSV::Script::Script.new : BSV::Script::Script.from_asm(unlock_asm)
    lock = lock_asm.empty? ? BSV::Script::Script.new : BSV::Script::Script.from_asm(lock_asm)
    described_class.evaluate(unlock, lock)
  end

  describe 'OP_IF / OP_ENDIF' do
    it 'executes true branch' do
      expect(evaluate('', 'OP_1 OP_IF OP_1 OP_ENDIF')).to be true
    end

    it 'skips false branch' do
      # OP_0 IF pushes nothing (skipped), ENDIF. Stack has just the 1 from unlock.
      expect(evaluate('OP_1', 'OP_0 OP_IF OP_0 OP_ENDIF')).to be true
    end

    it 'raises on unbalanced IF (missing ENDIF)' do
      expect do
        evaluate('', 'OP_1 OP_IF OP_1')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:unbalanced_conditional)
      }
    end

    it 'raises on ENDIF without IF' do
      expect do
        evaluate('', 'OP_1 OP_ENDIF')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:unbalanced_conditional)
      }
    end
  end

  describe 'OP_NOTIF / OP_ENDIF' do
    it 'executes when condition is false' do
      expect(evaluate('', 'OP_0 OP_NOTIF OP_1 OP_ENDIF')).to be true
    end

    it 'skips when condition is true' do
      expect(evaluate('OP_1', 'OP_1 OP_NOTIF OP_0 OP_ENDIF')).to be true
    end
  end

  describe 'OP_IF / OP_ELSE / OP_ENDIF' do
    it 'executes true branch, skips else' do
      expect(evaluate('', 'OP_1 OP_IF OP_1 OP_ELSE OP_0 OP_ENDIF')).to be true
    end

    it 'skips true branch, executes else' do
      expect(evaluate('', 'OP_0 OP_IF OP_0 OP_ELSE OP_1 OP_ENDIF')).to be true
    end

    it 'allows multiple ELSE branches per IF in relaxed (no-flags) mode' do
      # OP_0 IF (skip) ELSE 1 (exec → push 1) ELSE (skip) ENDIF → stack [1]
      expect(evaluate('', 'OP_0 OP_IF OP_0 OP_ELSE OP_1 OP_ELSE OP_0 OP_ENDIF')).to be true
    end

    it 'rejects multiple ELSE with explicit post-Genesis flags' do
      unlock = BSV::Script::Script.from_asm('OP_0')
      lock = BSV::Script::Script.from_asm('OP_IF OP_0 OP_ELSE OP_1 OP_ELSE OP_0 OP_ENDIF')
      expect do
        described_class.evaluate(unlock, lock, flags: %w[UTXO_AFTER_GENESIS])
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:unbalanced_conditional)
      }
    end

    it 'raises on ELSE without IF' do
      expect do
        evaluate('', 'OP_1 OP_ELSE')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:unbalanced_conditional)
      }
    end
  end

  describe 'nested conditionals' do
    it 'handles nested IF inside true branch' do
      expect(evaluate('', 'OP_1 OP_IF OP_1 OP_IF OP_1 OP_ENDIF OP_ENDIF')).to be true
    end

    it 'skips nested IF inside false branch' do
      # Outer IF is false → everything inside is skipped, including nested IF/ENDIF
      expect(evaluate('OP_1', 'OP_0 OP_IF OP_1 OP_IF OP_0 OP_ENDIF OP_ENDIF')).to be true
    end

    it 'skips nested IF/ELSE inside false branch' do
      # Nothing inside the outer false branch executes
      expect(evaluate('OP_1', 'OP_0 OP_IF OP_1 OP_IF OP_0 OP_ELSE OP_0 OP_ENDIF OP_ENDIF')).to be true
    end

    it 'handles nested IF inside else branch' do
      expect(evaluate('', 'OP_0 OP_IF OP_0 OP_ELSE OP_1 OP_IF OP_1 OP_ENDIF OP_ENDIF')).to be true
    end
  end

  describe 'OP_VERIFY' do
    it 'succeeds on truthy value' do
      expect(evaluate('', 'OP_1 OP_1 OP_VERIFY')).to be true
    end

    it 'raises on falsy value' do
      expect do
        evaluate('', 'OP_0 OP_VERIFY')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:verify_failed)
      }
    end
  end

  describe 'OP_RETURN' do
    it 'terminates execution successfully (after genesis)' do
      # OP_RETURN in lock script after pushing truthy value
      expect(evaluate('OP_1', 'OP_RETURN')).to be true
    end

    it 'ignores remaining opcodes after OP_RETURN' do
      # Invalid opcodes after OP_RETURN are never reached
      expect(evaluate('OP_1', 'OP_RETURN OP_RESERVED')).to be true
    end

    it 'raises on unbalanced conditional after OP_RETURN' do
      # IF 5 RETURN — missing ENDIF, conditional balance must be checked
      expect do
        evaluate('OP_1', 'OP_IF OP_5 OP_RETURN')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:unbalanced_conditional)
      }
    end

    it 'succeeds when conditionals are balanced before OP_RETURN' do
      # IF 1 ENDIF RETURN — balanced, then early return
      expect(evaluate('OP_1', 'OP_1 OP_IF OP_RETURN OP_ENDIF')).to be true
    end
  end

  describe 'OP_NOP' do
    it 'does nothing' do
      expect(evaluate('', 'OP_1 OP_NOP')).to be true
    end
  end

  describe 'OP_NOP1..OP_NOP10 (including CLTV/CSV)' do
    it 'treats CHECKLOCKTIMEVERIFY as NOP' do
      expect(evaluate('', 'OP_1 OP_CHECKLOCKTIMEVERIFY')).to be true
    end

    it 'treats CHECKSEQUENCEVERIFY as NOP' do
      expect(evaluate('', 'OP_1 OP_CHECKSEQUENCEVERIFY')).to be true
    end

    # OP_NOP4 is an alias for OP_SUBSTR (0xb3) — now implemented as a
    # Chronicle splice opcode, not a NOP. It requires three stack items.
    it 'OP_NOP4 (OP_SUBSTR) executes as OP_SUBSTR, not as a NOP' do
      expect do
        evaluate('', 'OP_1 OP_NOP4')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_stack_operation)
      }
    end
  end

  describe 'reserved opcodes' do
    it 'OP_RESERVED raises when executing' do
      expect do
        evaluate('', 'OP_RESERVED')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:reserved_opcode)
      }
    end

    # OP_VER is now implemented: pushes 4-byte LE tx version.
    # Without transaction context (Interpreter.evaluate), raises :missing_tx_context.
    it 'OP_VER raises :missing_tx_context when called without transaction context' do
      expect do
        evaluate('', 'OP_VER')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:missing_tx_context)
      }
    end

    it 'OP_RESERVED1 raises when executing' do
      expect do
        evaluate('', 'OP_RESERVED1')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:reserved_opcode)
      }
    end

    it 'OP_RESERVED2 raises when executing' do
      expect do
        evaluate('', 'OP_RESERVED2')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:reserved_opcode)
      }
    end

    it 'OP_RESERVED is skipped in non-executing branch' do
      expect(evaluate('OP_1', 'OP_0 OP_IF OP_RESERVED OP_ENDIF')).to be true
    end
  end

  describe 'OP_VERIF / OP_VERNOTIF (version-conditional branching)' do
    # These opcodes require transaction context to compare against the tx version.
    # Without a transaction, tx_version_matches? returns false (else branch taken).

    it 'OP_VERIF raises :invalid_stack_operation on empty stack (executing branch)' do
      expect do
        evaluate('', 'OP_VERIF OP_1 OP_ELSE OP_0 OP_ENDIF')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_stack_operation)
      }
    end

    it 'OP_VERNOTIF raises :invalid_stack_operation on empty stack (executing branch)' do
      expect do
        evaluate('', 'OP_VERNOTIF OP_1 OP_ELSE OP_0 OP_ENDIF')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_stack_operation)
      }
    end

    it 'OP_VERIF without tx context always takes else branch (not an error)' do
      # Without tx, tx_version_matches? returns false → else branch → stack has 1
      expect(evaluate('', 'OP_0 OP_VERIF OP_0 OP_ELSE OP_1 OP_ENDIF')).to be true
    end

    it 'OP_VERNOTIF without tx context always takes true branch (not an error)' do
      # Without tx, tx_version_matches? returns false → VERNOTIF true branch → stack has 1
      expect(evaluate('', 'OP_0 OP_VERNOTIF OP_1 OP_ELSE OP_0 OP_ENDIF')).to be true
    end

    it 'OP_VERIF is tracked for nesting depth in non-executing branch' do
      # OP_0 means outer IF is false; inner VERIF is in a non-executing branch and
      # must be tracked for nesting (so its ENDIF is consumed correctly).
      # After both ENDIFs, stack has OP_1 from unlock.
      expect(evaluate('OP_1', 'OP_0 OP_IF OP_VERIF OP_ENDIF OP_ENDIF')).to be true
    end

    it 'OP_VERNOTIF is tracked for nesting depth in non-executing branch' do
      expect(evaluate('OP_1', 'OP_0 OP_IF OP_VERNOTIF OP_ENDIF OP_ENDIF')).to be true
    end
  end
end
