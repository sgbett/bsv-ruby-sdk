# frozen_string_literal: true

require 'spec_helper'

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

  describe 'OP_EQUAL' do
    it 'pushes true for equal byte arrays' do
      expect(evaluate('OP_5', 'OP_5 OP_EQUAL')).to be true
    end

    it 'pushes false for unequal byte arrays' do
      expect do
        evaluate('', 'OP_5 OP_6 OP_EQUAL')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:eval_false)
      }
    end

    it 'compares raw bytes, not numeric value' do
      interp = build_interpreter
      interp.dstack.push_bytes("\x01\x00".b) # 1 as 2 bytes
      interp.dstack.push_bytes("\x01".b)     # 1 as 1 byte
      interp.send(:op_equal)
      expect(interp.dstack.pop_bool).to be false
    end
  end

  describe 'OP_EQUALVERIFY' do
    it 'succeeds for equal values' do
      expect(evaluate('OP_3', 'OP_3 OP_EQUALVERIFY OP_1')).to be true
    end

    it 'raises for unequal values' do
      expect do
        evaluate('', 'OP_3 OP_4 OP_EQUALVERIFY')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:equalverify_failed)
      }
    end
  end

  describe 'OP_AND' do
    it 'computes bitwise AND' do
      interp = build_interpreter
      interp.dstack.push_bytes("\xff\x0f".b)
      interp.dstack.push_bytes("\xf0\xff".b)
      interp.send(:op_and)
      expect(interp.dstack.pop_bytes).to eq("\xf0\x0f".b)
    end

    it 'raises for different-length arrays' do
      interp = build_interpreter
      interp.dstack.push_bytes("\xff".b)
      interp.dstack.push_bytes("\xff\x00".b)
      expect do
        interp.send(:op_and)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_input_length)
      }
    end
  end

  describe 'OP_OR' do
    it 'computes bitwise OR' do
      interp = build_interpreter
      interp.dstack.push_bytes("\xf0\x00".b)
      interp.dstack.push_bytes("\x0f\xff".b)
      interp.send(:op_or)
      expect(interp.dstack.pop_bytes).to eq("\xff\xff".b)
    end
  end

  describe 'OP_XOR' do
    it 'computes bitwise XOR' do
      interp = build_interpreter
      interp.dstack.push_bytes("\xff\xff".b)
      interp.dstack.push_bytes("\xf0\x0f".b)
      interp.send(:op_xor)
      expect(interp.dstack.pop_bytes).to eq("\x0f\xf0".b)
    end
  end

  describe 'OP_INVERT' do
    it 'flips all bits' do
      interp = build_interpreter
      interp.dstack.push_bytes("\xf0\x0f\x00\xff".b)
      interp.send(:op_invert)
      expect(interp.dstack.pop_bytes).to eq("\x0f\xf0\xff\x00".b)
    end

    it 'double invert returns original' do
      interp = build_interpreter
      original = "\xde\xad\xbe\xef".b
      interp.dstack.push_bytes(original.dup)
      interp.send(:op_invert)
      interp.send(:op_invert)
      expect(interp.dstack.pop_bytes).to eq(original)
    end
  end
end
