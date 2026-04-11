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

  describe 'OP_CAT' do
    it 'concatenates two byte arrays' do
      interp = build_interpreter
      interp.dstack.push_bytes("\xde\xad".b)
      interp.dstack.push_bytes("\xbe\xef".b)
      interp.send(:op_cat)
      expect(interp.dstack.pop_bytes).to eq("\xde\xad\xbe\xef".b)
    end

    it 'handles empty left operand' do
      interp = build_interpreter
      interp.dstack.push_bytes(''.b)
      interp.dstack.push_bytes("\xff".b)
      interp.send(:op_cat)
      expect(interp.dstack.pop_bytes).to eq("\xff".b)
    end

    it 'handles empty right operand' do
      interp = build_interpreter
      interp.dstack.push_bytes("\xff".b)
      interp.dstack.push_bytes(''.b)
      interp.send(:op_cat)
      expect(interp.dstack.pop_bytes).to eq("\xff".b)
    end
  end

  describe 'OP_SPLIT' do
    it 'splits at the given position' do
      interp = build_interpreter
      interp.dstack.push_bytes("\xde\xad\xbe\xef".b)
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(2))
      interp.send(:op_split)
      right = interp.dstack.pop_bytes
      left = interp.dstack.pop_bytes
      expect(left).to eq("\xde\xad".b)
      expect(right).to eq("\xbe\xef".b)
    end

    it 'splits at position 0 (empty left)' do
      interp = build_interpreter
      interp.dstack.push_bytes("\xab\xcd".b)
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(0))
      interp.send(:op_split)
      right = interp.dstack.pop_bytes
      left = interp.dstack.pop_bytes
      expect(left).to eq(''.b)
      expect(right).to eq("\xab\xcd".b)
    end

    it 'splits at end (empty right)' do
      interp = build_interpreter
      interp.dstack.push_bytes("\xab\xcd".b)
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(2))
      interp.send(:op_split)
      right = interp.dstack.pop_bytes
      left = interp.dstack.pop_bytes
      expect(left).to eq("\xab\xcd".b)
      expect(right).to eq(''.b)
    end

    it 'raises on negative position' do
      interp = build_interpreter
      interp.dstack.push_bytes("\xab\xcd".b)
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(-1))
      expect do
        interp.send(:op_split)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_input_length)
      }
    end

    it 'raises when position exceeds data length' do
      interp = build_interpreter
      interp.dstack.push_bytes("\xab\xcd".b)
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(3))
      expect do
        interp.send(:op_split)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_input_length)
      }
    end
  end

  describe 'OP_SIZE' do
    it 'pushes the byte length without popping' do
      interp = build_interpreter
      interp.dstack.push_bytes("\xde\xad\xbe\xef".b)
      interp.send(:op_size)
      size = interp.dstack.pop_int.value
      data = interp.dstack.pop_bytes
      expect(size).to eq(4)
      expect(data).to eq("\xde\xad\xbe\xef".b)
    end

    it 'returns 0 for empty data' do
      interp = build_interpreter
      interp.dstack.push_bytes(''.b)
      interp.send(:op_size)
      expect(interp.dstack.pop_int.value).to eq(0)
    end

    it 'works via ASM with SIZE and SWAP/DROP' do
      # Push 3-byte data, SIZE gives 3, SWAP to put size on top, drop original
      expect(evaluate('', 'OP_5 OP_SIZE OP_NIP')).to be true
    end
  end

  describe 'OP_NUM2BIN' do
    it 'pads a number to the requested size' do
      interp = build_interpreter
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(1))
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(4))
      interp.send(:op_num2bin)
      expect(interp.dstack.pop_bytes).to eq("\x01\x00\x00\x00".b)
    end

    it 'preserves sign bit when padding' do
      interp = build_interpreter
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(-1))
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(2))
      interp.send(:op_num2bin)
      expect(interp.dstack.pop_bytes).to eq("\x01\x80".b)
    end

    it 'returns already-minimal encoding when size matches' do
      interp = build_interpreter
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(256))
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(2))
      interp.send(:op_num2bin)
      expect(interp.dstack.pop_bytes).to eq("\x00\x01".b)
    end

    it 'pads zero to requested size' do
      interp = build_interpreter
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(0))
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(4))
      interp.send(:op_num2bin)
      expect(interp.dstack.pop_bytes).to eq("\x00\x00\x00\x00".b)
    end

    it 'raises when number cannot fit in requested size' do
      interp = build_interpreter
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(256))
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(1))
      expect do
        interp.send(:op_num2bin)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:impossible_encoding)
      }
    end

    it 'raises on negative size' do
      interp = build_interpreter
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(1))
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(-1))
      expect do
        interp.send(:op_num2bin)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_input_length)
      }
    end
  end

  describe 'OP_BIN2NUM' do
    it 'minimally encodes a padded number' do
      interp = build_interpreter
      interp.dstack.push_bytes("\x01\x00\x00\x00".b)
      interp.send(:op_bin2num)
      expect(interp.dstack.pop_bytes).to eq("\x01".b)
    end

    it 'minimally encodes a negative padded number' do
      interp = build_interpreter
      interp.dstack.push_bytes("\x01\x00\x80".b)
      interp.send(:op_bin2num)
      expect(interp.dstack.pop_bytes).to eq("\x81".b)
    end

    it 'returns empty for all-zero input' do
      interp = build_interpreter
      interp.dstack.push_bytes("\x00\x00\x00".b)
      interp.send(:op_bin2num)
      expect(interp.dstack.pop_bytes).to eq(''.b)
    end

    it 'round-trips with NUM2BIN' do
      interp = build_interpreter
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(42))
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(4))
      interp.send(:op_num2bin)
      interp.send(:op_bin2num)
      expect(interp.dstack.pop_int.value).to eq(42)
    end
  end
end
