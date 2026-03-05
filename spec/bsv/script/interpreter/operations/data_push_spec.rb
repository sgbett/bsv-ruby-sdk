# frozen_string_literal: true

RSpec.describe BSV::Script::Interpreter do
  def build_interpreter
    empty = BSV::Script::Script.new
    described_class.send(:new, unlock_script: empty, lock_script: empty)
  end

  def evaluate(unlock_asm, lock_asm)
    unlock = unlock_asm.empty? ? BSV::Script::Script.new : BSV::Script::Script.from_asm(unlock_asm)
    lock = lock_asm.empty? ? BSV::Script::Script.new : BSV::Script::Script.from_asm(lock_asm)
    described_class.evaluate(unlock, lock)
  end

  describe 'OP_0 / OP_FALSE' do
    it 'pushes empty byte string' do
      interp = build_interpreter
      interp.send(:op_false)
      expect(interp.dstack.pop_bytes).to eq(''.b)
    end

    it 'pushes a falsy value' do
      expect do
        evaluate('', 'OP_0')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:eval_false)
      }
    end

    it 'is consumable by OP_DROP' do
      expect(evaluate('OP_1', 'OP_0 OP_DROP')).to be true
    end
  end

  describe 'OP_1NEGATE' do
    it 'pushes -1' do
      interp = build_interpreter
      interp.send(:op_1negate)
      expect(interp.dstack.pop_int.value).to eq(-1)
    end

    it 'is truthy' do
      expect(evaluate('', 'OP_1NEGATE')).to be true
    end
  end

  describe 'OP_1 through OP_16' do
    (1..16).each do |n|
      it "OP_#{n} pushes #{n}" do
        interp = build_interpreter
        opcode = BSV::Script::Opcodes::OP_1 + n - 1
        interp.send(:op_n, opcode)
        expect(interp.dstack.pop_int.value).to eq(n)
      end
    end

    it 'all push truthy values' do
      (1..16).each do |n|
        expect(evaluate('', "OP_#{n}")).to be true
      end
    end
  end

  describe 'data push (1-75 bytes)' do
    it 'pushes 1-byte data' do
      expect(evaluate('', 'ff')).to be true
    end

    it 'pushes multi-byte data' do
      interp = build_interpreter
      chunk = BSV::Script::Chunk.new(opcode: 0x04, data: "\xde\xad\xbe\xef".b)
      interp.send(:op_push_data, chunk)
      expect(interp.dstack.pop_bytes).to eq("\xde\xad\xbe\xef".b)
    end

    it 'pushes 75 bytes' do
      hex = 'ab' * 75
      expect(evaluate('', hex)).to be true
    end
  end

  describe 'OP_PUSHDATA1' do
    it 'pushes 76 bytes' do
      hex = 'cd' * 76
      expect(evaluate('', hex)).to be true
    end

    it 'pushes 255 bytes' do
      hex = 'ef' * 255
      expect(evaluate('', hex)).to be true
    end
  end

  describe 'OP_PUSHDATA2' do
    it 'pushes 256 bytes' do
      hex = 'ab' * 256
      expect(evaluate('', hex)).to be true
    end
  end
end
