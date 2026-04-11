# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Script::Stack do
  subject(:stack) { described_class.new }

  describe 'push/pop bytes' do
    it 'pushes and pops binary data' do
      stack.push_bytes("\x01\x02\x03".b)
      expect(stack.pop_bytes).to eq("\x01\x02\x03".b)
    end

    it 'raises on pop from empty stack' do
      expect { stack.pop_bytes }.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_stack_operation)
      }
    end

    it 'operates LIFO' do
      stack.push_bytes('a'.b)
      stack.push_bytes('b'.b)
      expect(stack.pop_bytes).to eq('b'.b)
      expect(stack.pop_bytes).to eq('a'.b)
    end
  end

  describe 'push/pop int' do
    it 'round-trips a ScriptNumber' do
      num = BSV::Script::ScriptNumber.new(42)
      stack.push_int(num)
      result = stack.pop_int
      expect(result.value).to eq(42)
    end

    it 'round-trips zero' do
      stack.push_int(BSV::Script::ScriptNumber.new(0))
      expect(stack.pop_int.value).to eq(0)
    end

    it 'round-trips negative numbers' do
      stack.push_int(BSV::Script::ScriptNumber.new(-128))
      expect(stack.pop_int.value).to eq(-128)
    end
  end

  describe 'push/pop bool' do
    it 'pushes true as 0x01' do
      stack.push_bool(true)
      expect(stack.pop_bytes).to eq("\x01".b)
    end

    it 'pushes false as empty' do
      stack.push_bool(false)
      expect(stack.pop_bytes).to eq(''.b)
    end

    it 'pops true for non-zero' do
      stack.push_bytes("\x05".b)
      expect(stack.pop_bool).to be true
    end

    it 'pops false for empty' do
      stack.push_bytes(''.b)
      expect(stack.pop_bool).to be false
    end

    it 'pops false for all-zero bytes' do
      stack.push_bytes("\x00\x00\x00".b)
      expect(stack.pop_bool).to be false
    end

    it 'pops false for negative zero (0x80)' do
      stack.push_bytes("\x80".b)
      expect(stack.pop_bool).to be false
    end

    it 'pops true for 0x80 in non-last position' do
      stack.push_bytes("\x80\x01".b)
      expect(stack.pop_bool).to be true
    end

    it 'pops false for 0x00...0x80 (negative zero multi-byte)' do
      stack.push_bytes("\x00\x80".b)
      expect(stack.pop_bool).to be false
    end
  end

  describe 'peek' do
    before do
      stack.push_bytes('a'.b)
      stack.push_bytes('b'.b)
      stack.push_bytes('c'.b)
    end

    it 'peeks at top (idx=0)' do
      expect(stack.peek_bytes(0)).to eq('c'.b)
    end

    it 'peeks deeper into stack' do
      expect(stack.peek_bytes(1)).to eq('b'.b)
      expect(stack.peek_bytes(2)).to eq('a'.b)
    end

    it 'does not remove the item' do
      stack.peek_bytes(0)
      expect(stack.depth).to eq(3)
    end

    it 'raises on out-of-bounds index' do
      expect { stack.peek_bytes(3) }.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_stack_operation)
      }
    end

    it 'raises on negative index' do
      expect { stack.peek_bytes(-1) }.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_stack_operation)
      }
    end
  end

  describe '#depth and #empty?' do
    it 'starts empty' do
      expect(stack).to be_empty
      expect(stack.depth).to eq(0)
    end

    it 'tracks depth' do
      stack.push_bytes('a'.b)
      expect(stack.depth).to eq(1)
      expect(stack).not_to be_empty
    end
  end

  describe '#clear' do
    it 'removes all items' do
      stack.push_bytes('a'.b)
      stack.push_bytes('b'.b)
      stack.clear
      expect(stack).to be_empty
    end
  end

  describe '#dup_n' do
    it 'duplicates top 1 item (OP_DUP)' do
      stack.push_bytes('a'.b)
      stack.push_bytes('b'.b)
      stack.dup_n(1)
      expect(stack.depth).to eq(3)
      expect(stack.pop_bytes).to eq('b'.b)
      expect(stack.pop_bytes).to eq('b'.b)
    end

    it 'duplicates top 2 items (OP_2DUP)' do
      stack.push_bytes('a'.b)
      stack.push_bytes('b'.b)
      stack.dup_n(2)
      expect(stack.depth).to eq(4)
      expect(stack.pop_bytes).to eq('b'.b)
      expect(stack.pop_bytes).to eq('a'.b)
      expect(stack.pop_bytes).to eq('b'.b)
      expect(stack.pop_bytes).to eq('a'.b)
    end

    it 'duplicates top 3 items (OP_3DUP)' do
      stack.push_bytes('a'.b)
      stack.push_bytes('b'.b)
      stack.push_bytes('c'.b)
      stack.dup_n(3)
      expect(stack.depth).to eq(6)
    end

    it 'raises when n < 1' do
      expect { stack.dup_n(0) }.to raise_error(BSV::Script::ScriptError)
    end

    it 'raises when stack too small' do
      stack.push_bytes('a'.b)
      expect { stack.dup_n(2) }.to raise_error(BSV::Script::ScriptError)
    end
  end

  describe '#drop_n' do
    before do
      stack.push_bytes('a'.b)
      stack.push_bytes('b'.b)
      stack.push_bytes('c'.b)
    end

    it 'drops top 1 item (OP_DROP)' do
      stack.drop_n(1)
      expect(stack.depth).to eq(2)
      expect(stack.peek_bytes(0)).to eq('b'.b)
    end

    it 'drops top 2 items (OP_2DROP)' do
      stack.drop_n(2)
      expect(stack.depth).to eq(1)
      expect(stack.peek_bytes(0)).to eq('a'.b)
    end

    it 'raises when n < 1' do
      expect { stack.drop_n(0) }.to raise_error(BSV::Script::ScriptError)
    end

    it 'raises when stack too small' do
      expect { stack.drop_n(4) }.to raise_error(BSV::Script::ScriptError)
    end
  end

  describe '#nip_n' do
    before do
      stack.push_bytes('a'.b)
      stack.push_bytes('b'.b)
      stack.push_bytes('c'.b)
    end

    it 'removes top item (idx=0)' do
      stack.nip_n(0)
      expect(stack.depth).to eq(2)
      expect(stack.peek_bytes(0)).to eq('b'.b)
    end

    it 'removes second item (idx=1)' do
      stack.nip_n(1)
      expect(stack.depth).to eq(2)
      expect(stack.peek_bytes(0)).to eq('c'.b)
      expect(stack.peek_bytes(1)).to eq('a'.b)
    end

    it 'removes bottom item' do
      stack.nip_n(2)
      expect(stack.depth).to eq(2)
      expect(stack.peek_bytes(0)).to eq('c'.b)
      expect(stack.peek_bytes(1)).to eq('b'.b)
    end
  end

  describe '#rot_n' do
    it 'rotates top 3 items (OP_ROT)' do
      stack.push_bytes('a'.b)
      stack.push_bytes('b'.b)
      stack.push_bytes('c'.b)
      stack.rot_n(1)
      expect(stack.pop_bytes).to eq('a'.b)
      expect(stack.pop_bytes).to eq('c'.b)
      expect(stack.pop_bytes).to eq('b'.b)
    end

    it 'rotates pairs (OP_2ROT)' do
      %w[a b c d e f].each { |v| stack.push_bytes(v.b) }
      stack.rot_n(2)
      expect(stack.pop_bytes).to eq('b'.b)
      expect(stack.pop_bytes).to eq('a'.b)
      expect(stack.pop_bytes).to eq('f'.b)
      expect(stack.pop_bytes).to eq('e'.b)
      expect(stack.pop_bytes).to eq('d'.b)
      expect(stack.pop_bytes).to eq('c'.b)
    end

    it 'raises when n < 1' do
      expect { stack.rot_n(0) }.to raise_error(BSV::Script::ScriptError)
    end

    it 'raises when stack too small' do
      stack.push_bytes('a'.b)
      stack.push_bytes('b'.b)
      expect { stack.rot_n(1) }.to raise_error(BSV::Script::ScriptError)
    end
  end

  describe '#swap_n' do
    it 'swaps top 2 items (OP_SWAP)' do
      stack.push_bytes('a'.b)
      stack.push_bytes('b'.b)
      stack.swap_n(1)
      expect(stack.pop_bytes).to eq('a'.b)
      expect(stack.pop_bytes).to eq('b'.b)
    end

    it 'swaps pairs (OP_2SWAP)' do
      %w[a b c d].each { |v| stack.push_bytes(v.b) }
      stack.swap_n(2)
      expect(stack.pop_bytes).to eq('b'.b)
      expect(stack.pop_bytes).to eq('a'.b)
      expect(stack.pop_bytes).to eq('d'.b)
      expect(stack.pop_bytes).to eq('c'.b)
    end

    it 'raises when stack too small' do
      stack.push_bytes('a'.b)
      expect { stack.swap_n(1) }.to raise_error(BSV::Script::ScriptError)
    end
  end

  describe '#over_n' do
    it 'copies second to top (OP_OVER)' do
      stack.push_bytes('a'.b)
      stack.push_bytes('b'.b)
      stack.over_n(1)
      expect(stack.depth).to eq(3)
      expect(stack.pop_bytes).to eq('a'.b)
      expect(stack.pop_bytes).to eq('b'.b)
      expect(stack.pop_bytes).to eq('a'.b)
    end

    it 'copies pairs (OP_2OVER)' do
      %w[a b c d].each { |v| stack.push_bytes(v.b) }
      stack.over_n(2)
      expect(stack.depth).to eq(6)
      expect(stack.pop_bytes).to eq('b'.b)
      expect(stack.pop_bytes).to eq('a'.b)
      expect(stack.pop_bytes).to eq('d'.b)
      expect(stack.pop_bytes).to eq('c'.b)
    end

    it 'raises when stack too small' do
      stack.push_bytes('a'.b)
      expect { stack.over_n(1) }.to raise_error(BSV::Script::ScriptError)
    end
  end

  describe '#pick_n' do
    before do
      stack.push_bytes('a'.b)
      stack.push_bytes('b'.b)
      stack.push_bytes('c'.b)
    end

    it 'copies top (idx=0)' do
      stack.pick_n(0)
      expect(stack.depth).to eq(4)
      expect(stack.pop_bytes).to eq('c'.b)
    end

    it 'copies deeper item' do
      stack.pick_n(2)
      expect(stack.depth).to eq(4)
      expect(stack.pop_bytes).to eq('a'.b)
    end

    it 'raises on out-of-bounds' do
      expect { stack.pick_n(3) }.to raise_error(BSV::Script::ScriptError)
    end
  end

  describe '#roll_n' do
    before do
      stack.push_bytes('a'.b)
      stack.push_bytes('b'.b)
      stack.push_bytes('c'.b)
    end

    it 'moves top (idx=0) — no change' do
      stack.roll_n(0)
      expect(stack.depth).to eq(3)
      expect(stack.pop_bytes).to eq('c'.b)
    end

    it 'moves deeper item to top' do
      stack.roll_n(2)
      expect(stack.depth).to eq(3)
      expect(stack.pop_bytes).to eq('a'.b)
      expect(stack.pop_bytes).to eq('c'.b)
      expect(stack.pop_bytes).to eq('b'.b)
    end

    it 'raises on out-of-bounds' do
      expect { stack.roll_n(3) }.to raise_error(BSV::Script::ScriptError)
    end
  end

  describe '#tuck' do
    it 'copies top before second' do
      stack.push_bytes('a'.b)
      stack.push_bytes('b'.b)
      stack.tuck
      expect(stack.depth).to eq(3)
      expect(stack.pop_bytes).to eq('b'.b)
      expect(stack.pop_bytes).to eq('a'.b)
      expect(stack.pop_bytes).to eq('b'.b)
    end

    it 'raises when stack too small' do
      stack.push_bytes('a'.b)
      expect { stack.tuck }.to raise_error(BSV::Script::ScriptError)
    end
  end

  describe '.cast_bool' do
    it 'returns false for empty' do
      expect(described_class.cast_bool(''.b)).to be false
    end

    it 'returns false for all zeros' do
      expect(described_class.cast_bool("\x00\x00".b)).to be false
    end

    it 'returns false for negative zero' do
      expect(described_class.cast_bool("\x80".b)).to be false
    end

    it 'returns false for multi-byte negative zero' do
      expect(described_class.cast_bool("\x00\x80".b)).to be false
    end

    it 'returns true for non-zero' do
      expect(described_class.cast_bool("\x01".b)).to be true
    end

    it 'returns true for 0x80 in non-last position' do
      expect(described_class.cast_bool("\x80\x00".b)).to be true
    end

    it 'returns false for nil' do
      expect(described_class.cast_bool(nil)).to be false
    end
  end
end
