# frozen_string_literal: true

RSpec.describe BSV::Script::Interpreter do # rubocop:disable RSpec/SpecFilePathFormat
  def evaluate(unlock_asm, lock_asm)
    unlock = unlock_asm.empty? ? BSV::Script::Script.new : BSV::Script::Script.from_asm(unlock_asm)
    lock = lock_asm.empty? ? BSV::Script::Script.new : BSV::Script::Script.from_asm(lock_asm)
    described_class.evaluate(unlock, lock)
  end

  describe '.evaluate' do
    it 'returns true for simple truthy script' do
      expect(evaluate('', 'OP_1')).to be true
    end

    it 'executes unlock then lock script sequentially' do
      # Unlock pushes 1 and 2, lock drops 2, top is 1
      expect(evaluate('OP_1 OP_2', 'OP_DROP')).to be true
    end

    it 'carries data stack from unlock to lock' do
      # Unlock pushes data, lock duplicates and drops — proves data carried over
      expect(evaluate('deadbeef', 'OP_DUP OP_DROP')).to be true
    end

    it 'raises EMPTY_STACK when both scripts are empty' do
      expect do
        evaluate('', '')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:empty_stack)
      }
    end

    it 'raises EVAL_FALSE when top of stack is falsy' do
      expect do
        evaluate('', 'OP_0')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:eval_false)
      }
    end

    it 'raises INVALID_OPCODE for unhandled opcodes' do
      expect do
        evaluate('', 'OP_1 OP_INVALIDOPCODE')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_opcode)
      }
    end

    it 'clears alt stack between scripts' do
      # Unlock pushes 1 to alt stack, alt stack is cleared between scripts,
      # lock tries to pop from empty alt stack
      expect do
        evaluate('OP_1 OP_TOALTSTACK', 'OP_FROMALTSTACK')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_stack_operation)
      }
    end

    it 'only checks top of final stack for truthiness' do
      # Multiple items on stack — only top matters
      expect(evaluate('OP_0 OP_0 OP_0', 'OP_1')).to be true
    end
  end
end
