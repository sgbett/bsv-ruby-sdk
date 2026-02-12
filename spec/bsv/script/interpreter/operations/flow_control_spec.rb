# frozen_string_literal: true

RSpec.describe BSV::Script::Interpreter do # rubocop:disable RSpec/SpecFilePathFormat
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

    it 'raises on duplicate ELSE (after genesis)' do
      expect do
        evaluate('', 'OP_1 OP_IF OP_1 OP_ELSE OP_1 OP_ELSE OP_1 OP_ENDIF')
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

    it 'treats NOP4 as NOP' do
      expect(evaluate('', 'OP_1 OP_NOP4')).to be true
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

    it 'OP_VER raises when executing' do
      expect do
        evaluate('', 'OP_VER')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:reserved_opcode)
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

  describe 'always-illegal opcodes (OP_VERIF / OP_VERNOTIF)' do
    it 'OP_VERIF raises when executing' do
      expect do
        evaluate('', 'OP_VERIF')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:reserved_opcode)
      }
    end

    it 'OP_VERNOTIF raises when executing' do
      expect do
        evaluate('', 'OP_VERNOTIF')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:reserved_opcode)
      }
    end

    it 'OP_VERIF is silent in non-executing branch (after genesis)' do
      expect(evaluate('OP_1', 'OP_0 OP_IF OP_VERIF OP_ENDIF')).to be true
    end

    it 'OP_VERNOTIF is silent in non-executing branch (after genesis)' do
      expect(evaluate('OP_1', 'OP_0 OP_IF OP_VERNOTIF OP_ENDIF')).to be true
    end
  end
end
