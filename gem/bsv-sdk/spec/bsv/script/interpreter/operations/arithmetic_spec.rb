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

  describe 'OP_1ADD' do
    it 'increments by 1' do
      expect(evaluate('', 'OP_5 OP_1ADD OP_6 OP_NUMEQUAL')).to be true
    end

    it 'increments zero' do
      expect(evaluate('', 'OP_0 OP_1ADD')).to be true
    end
  end

  describe 'OP_1SUB' do
    it 'decrements by 1' do
      expect(evaluate('', 'OP_5 OP_1SUB OP_4 OP_NUMEQUAL')).to be true
    end
  end

  describe 'OP_NEGATE' do
    it 'negates positive to negative' do
      interp = build_interpreter
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(5))
      interp.send(:op_negate)
      expect(interp.dstack.pop_int.value).to eq(-5)
    end

    it 'negates negative to positive' do
      interp = build_interpreter
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(-5))
      interp.send(:op_negate)
      expect(interp.dstack.pop_int.value).to eq(5)
    end

    it 'negates zero to zero' do
      interp = build_interpreter
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(0))
      interp.send(:op_negate)
      expect(interp.dstack.pop_int.value).to eq(0)
    end
  end

  describe 'OP_ABS' do
    it 'leaves positive unchanged' do
      expect(evaluate('', 'OP_5 OP_ABS OP_5 OP_NUMEQUAL')).to be true
    end

    it 'makes negative positive' do
      interp = build_interpreter
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(-7))
      interp.send(:op_abs)
      expect(interp.dstack.pop_int.value).to eq(7)
    end
  end

  describe 'OP_NOT' do
    it 'returns 1 for zero' do
      expect(evaluate('', 'OP_0 OP_NOT')).to be true
    end

    it 'returns 0 for nonzero' do
      expect do
        evaluate('', 'OP_5 OP_NOT')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:eval_false)
      }
    end
  end

  describe 'OP_0NOTEQUAL' do
    it 'returns 0 for zero' do
      expect do
        evaluate('', 'OP_0 OP_0NOTEQUAL')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:eval_false)
      }
    end

    it 'returns 1 for nonzero' do
      expect(evaluate('', 'OP_5 OP_0NOTEQUAL')).to be true
    end
  end

  describe 'OP_ADD' do
    it 'adds two numbers' do
      expect(evaluate('', 'OP_3 OP_5 OP_ADD OP_8 OP_NUMEQUAL')).to be true
    end

    it 'handles negative numbers' do
      interp = build_interpreter
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(-3))
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(5))
      interp.send(:op_add)
      expect(interp.dstack.pop_int.value).to eq(2)
    end
  end

  describe 'OP_SUB' do
    it 'subtracts top from second' do
      expect(evaluate('', 'OP_8 OP_3 OP_SUB OP_5 OP_NUMEQUAL')).to be true
    end
  end

  describe 'OP_MUL' do
    it 'multiplies two numbers' do
      expect(evaluate('', 'OP_3 OP_4 OP_MUL OP_12 OP_NUMEQUAL')).to be true
    end
  end

  describe 'OP_DIV' do
    it 'divides with truncation toward zero' do
      interp = build_interpreter
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(7))
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(2))
      interp.send(:op_div)
      expect(interp.dstack.pop_int.value).to eq(3)
    end

    it 'truncates toward zero for negative result' do
      interp = build_interpreter
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(-7))
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(2))
      interp.send(:op_div)
      expect(interp.dstack.pop_int.value).to eq(-3)
    end

    it 'raises on division by zero' do
      expect do
        evaluate('', 'OP_5 OP_0 OP_DIV')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:divide_by_zero)
      }
    end
  end

  describe 'OP_MOD' do
    it 'computes remainder with sign of dividend' do
      interp = build_interpreter
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(7))
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(3))
      interp.send(:op_mod)
      expect(interp.dstack.pop_int.value).to eq(1)
    end

    it 'negative dividend gives negative remainder' do
      interp = build_interpreter
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(-7))
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(3))
      interp.send(:op_mod)
      expect(interp.dstack.pop_int.value).to eq(-1)
    end

    it 'raises on modulo by zero' do
      expect do
        evaluate('', 'OP_5 OP_0 OP_MOD')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:divide_by_zero)
      }
    end
  end

  describe 'OP_LSHIFT' do
    it 'shifts left by 1 bit' do
      interp = build_interpreter
      interp.dstack.push_bytes("\x01\x00".b)
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(1))
      interp.send(:op_lshift)
      expect(interp.dstack.pop_bytes).to eq("\x02\x00".b)
    end

    it 'carries between bytes' do
      interp = build_interpreter
      interp.dstack.push_bytes("\x00\x80".b)
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(1))
      interp.send(:op_lshift)
      expect(interp.dstack.pop_bytes).to eq("\x01\x00".b)
    end

    it 'shifts by 8 (full byte)' do
      interp = build_interpreter
      interp.dstack.push_bytes("\x00\xff".b)
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(8))
      interp.send(:op_lshift)
      expect(interp.dstack.pop_bytes).to eq("\xff\x00".b)
    end

    it 'zeroes when shift exceeds total bits' do
      interp = build_interpreter
      interp.dstack.push_bytes("\xff\xff".b)
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(16))
      interp.send(:op_lshift)
      expect(interp.dstack.pop_bytes).to eq("\x00\x00".b)
    end

    it 'raises on negative shift' do
      interp = build_interpreter
      interp.dstack.push_bytes("\xff".b)
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(-1))
      expect do
        interp.send(:op_lshift)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_input_length)
      }
    end
  end

  describe 'OP_RSHIFT' do
    it 'shifts right by 1 bit' do
      interp = build_interpreter
      interp.dstack.push_bytes("\x02\x00".b)
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(1))
      interp.send(:op_rshift)
      expect(interp.dstack.pop_bytes).to eq("\x01\x00".b)
    end

    it 'carries between bytes' do
      interp = build_interpreter
      interp.dstack.push_bytes("\x01\x00".b)
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(1))
      interp.send(:op_rshift)
      expect(interp.dstack.pop_bytes).to eq("\x00\x80".b)
    end

    it 'shifts by 8 (full byte)' do
      interp = build_interpreter
      interp.dstack.push_bytes("\xff\x00".b)
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(8))
      interp.send(:op_rshift)
      expect(interp.dstack.pop_bytes).to eq("\x00\xff".b)
    end

    it 'zeroes when shift exceeds total bits' do
      interp = build_interpreter
      interp.dstack.push_bytes("\xff\xff".b)
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(16))
      interp.send(:op_rshift)
      expect(interp.dstack.pop_bytes).to eq("\x00\x00".b)
    end
  end

  describe 'OP_BOOLAND' do
    it 'returns 1 when both nonzero' do
      expect(evaluate('', 'OP_3 OP_5 OP_BOOLAND')).to be true
    end

    it 'returns 0 when one is zero' do
      expect do
        evaluate('', 'OP_0 OP_5 OP_BOOLAND')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:eval_false)
      }
    end
  end

  describe 'OP_BOOLOR' do
    it 'returns 1 when either nonzero' do
      expect(evaluate('', 'OP_0 OP_5 OP_BOOLOR')).to be true
    end

    it 'returns 0 when both zero' do
      expect do
        evaluate('', 'OP_0 OP_0 OP_BOOLOR')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:eval_false)
      }
    end
  end

  describe 'OP_NUMEQUAL' do
    it 'returns 1 for equal numbers' do
      expect(evaluate('', 'OP_5 OP_5 OP_NUMEQUAL')).to be true
    end

    it 'returns 0 for unequal numbers' do
      expect do
        evaluate('', 'OP_5 OP_6 OP_NUMEQUAL')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:eval_false)
      }
    end
  end

  describe 'OP_NUMEQUALVERIFY' do
    it 'succeeds for equal values' do
      expect(evaluate('', 'OP_5 OP_5 OP_NUMEQUALVERIFY OP_1')).to be true
    end

    it 'raises for unequal values' do
      expect do
        evaluate('', 'OP_5 OP_6 OP_NUMEQUALVERIFY')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:numequalverify_failed)
      }
    end
  end

  describe 'OP_NUMNOTEQUAL' do
    it 'returns 1 for unequal numbers' do
      expect(evaluate('', 'OP_5 OP_6 OP_NUMNOTEQUAL')).to be true
    end

    it 'returns 0 for equal numbers' do
      expect do
        evaluate('', 'OP_5 OP_5 OP_NUMNOTEQUAL')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:eval_false)
      }
    end
  end

  describe 'OP_LESSTHAN' do
    it 'returns 1 when a < b' do
      expect(evaluate('', 'OP_3 OP_5 OP_LESSTHAN')).to be true
    end

    it 'returns 0 when a >= b' do
      expect do
        evaluate('', 'OP_5 OP_3 OP_LESSTHAN')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:eval_false)
      }
    end
  end

  describe 'OP_GREATERTHAN' do
    it 'returns 1 when a > b' do
      expect(evaluate('', 'OP_5 OP_3 OP_GREATERTHAN')).to be true
    end

    it 'returns 0 when a <= b' do
      expect do
        evaluate('', 'OP_3 OP_5 OP_GREATERTHAN')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:eval_false)
      }
    end
  end

  describe 'OP_LESSTHANOREQUAL' do
    it 'returns 1 when a <= b' do
      expect(evaluate('', 'OP_5 OP_5 OP_LESSTHANOREQUAL')).to be true
    end

    it 'returns 0 when a > b' do
      expect do
        evaluate('', 'OP_6 OP_5 OP_LESSTHANOREQUAL')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:eval_false)
      }
    end
  end

  describe 'OP_GREATERTHANOREQUAL' do
    it 'returns 1 when a >= b' do
      expect(evaluate('', 'OP_5 OP_5 OP_GREATERTHANOREQUAL')).to be true
    end

    it 'returns 0 when a < b' do
      expect do
        evaluate('', 'OP_4 OP_5 OP_GREATERTHANOREQUAL')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:eval_false)
      }
    end
  end

  describe 'OP_MIN' do
    it 'returns the smaller value' do
      expect(evaluate('', 'OP_3 OP_5 OP_MIN OP_3 OP_NUMEQUAL')).to be true
    end
  end

  describe 'OP_MAX' do
    it 'returns the larger value' do
      expect(evaluate('', 'OP_3 OP_5 OP_MAX OP_5 OP_NUMEQUAL')).to be true
    end
  end

  describe 'OP_WITHIN' do
    it 'returns 1 when x is within range [min, max)' do
      # Stack: x=3 min=1 max=5 → 1 <= 3 < 5 → true
      expect(evaluate('', 'OP_3 OP_1 OP_5 OP_WITHIN')).to be true
    end

    it 'returns 0 when x equals max (exclusive upper bound)' do
      expect do
        evaluate('', 'OP_5 OP_1 OP_5 OP_WITHIN')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:eval_false)
      }
    end

    it 'returns 1 when x equals min (inclusive lower bound)' do
      expect(evaluate('', 'OP_1 OP_1 OP_5 OP_WITHIN')).to be true
    end
  end

  describe 'OP_2MUL (Chronicle)' do
    it 'multiplies 1 by 2' do
      expect(evaluate('', 'OP_1 OP_2MUL OP_2 OP_EQUAL')).to be true
    end

    it 'multiplies 0 by 2' do
      expect(evaluate('', 'OP_0 OP_2MUL OP_0 OP_EQUAL')).to be true
    end

    it 'multiplies 8 by 2 to give 16' do
      expect(evaluate('', 'OP_8 OP_2MUL OP_16 OP_EQUAL')).to be true
    end

    it 'preserves sign: -1 * 2 = -2' do
      # -2 encodes as 0x82 in script number format
      expect(evaluate('', 'OP_1NEGATE OP_2MUL OP_2 OP_NEGATE OP_EQUAL')).to be true
    end

    it 'raises invalid_stack_operation on empty stack' do
      expect do
        evaluate('', 'OP_2MUL')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_stack_operation)
      }
    end

    it 'is skipped in non-executing branch' do
      expect(evaluate('OP_1', 'OP_0 OP_IF OP_2MUL OP_ENDIF')).to be true
    end
  end

  describe 'OP_2DIV (Chronicle)' do
    it 'divides 2 by 2 to give 1' do
      expect(evaluate('', 'OP_2 OP_2DIV OP_1 OP_EQUAL')).to be true
    end

    it 'divides 16 by 2 to give 8' do
      expect(evaluate('', 'OP_16 OP_2DIV OP_8 OP_EQUAL')).to be true
    end

    it 'truncates toward zero: 1 / 2 = 0' do
      expect(evaluate('', 'OP_1 OP_2DIV OP_0 OP_EQUAL')).to be true
    end

    it 'divides 0 by 2 to give 0' do
      expect(evaluate('', 'OP_0 OP_2DIV OP_0 OP_EQUAL')).to be true
    end

    it 'raises invalid_stack_operation on empty stack' do
      expect do
        evaluate('', 'OP_2DIV')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_stack_operation)
      }
    end

    it 'is skipped in non-executing branch' do
      expect(evaluate('OP_1', 'OP_0 OP_IF OP_2DIV OP_ENDIF')).to be true
    end
  end
end
