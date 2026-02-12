# frozen_string_literal: true

RSpec.describe BSV::Script::Interpreter do # rubocop:disable RSpec/SpecFilePathFormat
  def build_interpreter
    empty = BSV::Script::Script.new
    described_class.send(:new, unlock_script: empty, lock_script: empty)
  end

  def evaluate(unlock_asm, lock_asm)
    unlock = unlock_asm.empty? ? BSV::Script::Script.new : BSV::Script::Script.from_asm(unlock_asm)
    lock = lock_asm.empty? ? BSV::Script::Script.new : BSV::Script::Script.from_asm(lock_asm)
    described_class.evaluate(unlock, lock)
  end

  describe 'OP_TOALTSTACK / OP_FROMALTSTACK' do
    it 'moves item to alt stack and back' do
      interp = build_interpreter
      interp.dstack.push_bytes('hello'.b)
      interp.dstack.push_bytes('world'.b)

      interp.send(:op_toaltstack)
      expect(interp.dstack.depth).to eq(1)
      expect(interp.astack.depth).to eq(1)

      interp.send(:op_fromaltstack)
      expect(interp.dstack.depth).to eq(2)
      expect(interp.dstack.pop_bytes).to eq('world'.b)
    end

    it 'roundtrips through evaluate' do
      # unlock: [1, 2]. lock: TOALT moves 2 to alt, DROP removes 1, FROMALT pushes 2 back
      expect(evaluate('OP_1 OP_2', 'OP_TOALTSTACK OP_DROP OP_FROMALTSTACK')).to be true
    end
  end

  describe 'OP_IFDUP' do
    it 'duplicates truthy value' do
      interp = build_interpreter
      interp.dstack.push_bytes("\x01".b)
      interp.send(:op_ifdup)
      expect(interp.dstack.depth).to eq(2)
    end

    it 'does not duplicate falsy value' do
      interp = build_interpreter
      interp.dstack.push_bytes(''.b)
      interp.send(:op_ifdup)
      expect(interp.dstack.depth).to eq(1)
    end
  end

  describe 'OP_DEPTH' do
    it 'pushes current stack depth' do
      interp = build_interpreter
      interp.dstack.push_bytes('a'.b)
      interp.dstack.push_bytes('b'.b)
      interp.send(:op_depth)
      expect(interp.dstack.pop_int.value).to eq(2)
    end
  end

  describe 'OP_DROP' do
    it 'removes top item' do
      expect(evaluate('OP_1 OP_2', 'OP_DROP')).to be true
    end
  end

  describe 'OP_2DROP' do
    it 'removes top two items' do
      expect(evaluate('OP_1 OP_2 OP_3', 'OP_2DROP')).to be true
    end
  end

  describe 'OP_DUP' do
    it 'duplicates top item' do
      interp = build_interpreter
      interp.dstack.push_bytes('a'.b)
      interp.send(:op_dup)
      expect(interp.dstack.depth).to eq(2)
      expect(interp.dstack.pop_bytes).to eq('a'.b)
      expect(interp.dstack.pop_bytes).to eq('a'.b)
    end
  end

  describe 'OP_2DUP' do
    it 'duplicates top two items' do
      interp = build_interpreter
      interp.dstack.push_bytes('a'.b)
      interp.dstack.push_bytes('b'.b)
      interp.send(:op_2dup)
      expect(interp.dstack.depth).to eq(4)
    end
  end

  describe 'OP_3DUP' do
    it 'duplicates top three items' do
      interp = build_interpreter
      interp.dstack.push_bytes('a'.b)
      interp.dstack.push_bytes('b'.b)
      interp.dstack.push_bytes('c'.b)
      interp.send(:op_3dup)
      expect(interp.dstack.depth).to eq(6)
    end
  end

  describe 'OP_NIP' do
    it 'removes second-to-top item' do
      interp = build_interpreter
      interp.dstack.push_bytes('a'.b)
      interp.dstack.push_bytes('b'.b)
      interp.send(:op_nip)
      expect(interp.dstack.depth).to eq(1)
      expect(interp.dstack.pop_bytes).to eq('b'.b)
    end
  end

  describe 'OP_OVER' do
    it 'copies second item to top' do
      interp = build_interpreter
      interp.dstack.push_bytes('a'.b)
      interp.dstack.push_bytes('b'.b)
      interp.send(:op_over)
      expect(interp.dstack.depth).to eq(3)
      expect(interp.dstack.pop_bytes).to eq('a'.b)
    end
  end

  describe 'OP_2OVER' do
    it 'copies third and fourth items to top' do
      interp = build_interpreter
      %w[a b c d].each { |v| interp.dstack.push_bytes(v.b) }
      interp.send(:op_2over)
      expect(interp.dstack.depth).to eq(6)
      expect(interp.dstack.pop_bytes).to eq('b'.b)
      expect(interp.dstack.pop_bytes).to eq('a'.b)
    end
  end

  describe 'OP_PICK' do
    it 'copies nth item to top' do
      interp = build_interpreter
      interp.dstack.push_bytes('a'.b)
      interp.dstack.push_bytes('b'.b)
      interp.dstack.push_bytes('c'.b)
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(2))
      interp.send(:op_pick)
      expect(interp.dstack.pop_bytes).to eq('a'.b)
    end
  end

  describe 'OP_ROLL' do
    it 'moves nth item to top' do
      interp = build_interpreter
      interp.dstack.push_bytes('a'.b)
      interp.dstack.push_bytes('b'.b)
      interp.dstack.push_bytes('c'.b)
      interp.dstack.push_int(BSV::Script::ScriptNumber.new(2))
      interp.send(:op_roll)
      expect(interp.dstack.depth).to eq(3)
      expect(interp.dstack.pop_bytes).to eq('a'.b)
    end
  end

  describe 'OP_ROT' do
    it 'rotates top three items' do
      interp = build_interpreter
      interp.dstack.push_bytes('a'.b)
      interp.dstack.push_bytes('b'.b)
      interp.dstack.push_bytes('c'.b)
      interp.send(:op_rot)
      expect(interp.dstack.pop_bytes).to eq('a'.b)
      expect(interp.dstack.pop_bytes).to eq('c'.b)
      expect(interp.dstack.pop_bytes).to eq('b'.b)
    end
  end

  describe 'OP_2ROT' do
    it 'rotates top six items in pairs' do
      interp = build_interpreter
      %w[a b c d e f].each { |v| interp.dstack.push_bytes(v.b) }
      interp.send(:op_2rot)
      expect(interp.dstack.pop_bytes).to eq('b'.b)
      expect(interp.dstack.pop_bytes).to eq('a'.b)
    end
  end

  describe 'OP_SWAP' do
    it 'swaps top two items' do
      interp = build_interpreter
      interp.dstack.push_bytes('a'.b)
      interp.dstack.push_bytes('b'.b)
      interp.send(:op_swap)
      expect(interp.dstack.pop_bytes).to eq('a'.b)
      expect(interp.dstack.pop_bytes).to eq('b'.b)
    end
  end

  describe 'OP_2SWAP' do
    it 'swaps top two pairs' do
      interp = build_interpreter
      %w[a b c d].each { |v| interp.dstack.push_bytes(v.b) }
      interp.send(:op_2swap)
      expect(interp.dstack.pop_bytes).to eq('b'.b)
      expect(interp.dstack.pop_bytes).to eq('a'.b)
      expect(interp.dstack.pop_bytes).to eq('d'.b)
      expect(interp.dstack.pop_bytes).to eq('c'.b)
    end
  end

  describe 'OP_TUCK' do
    it 'copies top item before second' do
      interp = build_interpreter
      interp.dstack.push_bytes('a'.b)
      interp.dstack.push_bytes('b'.b)
      interp.send(:op_tuck)
      expect(interp.dstack.depth).to eq(3)
      expect(interp.dstack.pop_bytes).to eq('b'.b)
      expect(interp.dstack.pop_bytes).to eq('a'.b)
      expect(interp.dstack.pop_bytes).to eq('b'.b)
    end
  end
end
