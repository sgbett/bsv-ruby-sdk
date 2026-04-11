# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Script::Script do
  describe '.op_cat_lock' do
    it 'creates a script with OP_CAT <data> OP_EQUAL' do
      expected = 'hello world'
      script = described_class.op_cat_lock(expected)
      expect(script.op_cat?).to be true
      expect(script.type).to eq('opcat')
    end

    it 'round-trips through hex serialisation' do
      script = described_class.op_cat_lock('test data')
      rebuilt = described_class.from_hex(script.to_hex)
      expect(rebuilt.op_cat?).to be true
    end

    it 'round-trips through binary serialisation' do
      script = described_class.op_cat_lock('binary data')
      rebuilt = described_class.from_binary(script.to_binary)
      expect(rebuilt.op_cat?).to be true
    end
  end

  describe '.op_cat_unlock' do
    it 'creates a script pushing two data items' do
      script = described_class.op_cat_unlock('hello ', 'world')
      chunks = script.chunks
      expect(chunks.length).to eq(2)
      expect(chunks[0].data).to eq('hello '.b)
      expect(chunks[1].data).to eq('world'.b)
    end
  end

  describe 'interpreter verification' do
    it 'verifies when concatenation matches expected data' do
      expected = 'hello world'
      lock = described_class.op_cat_lock(expected)
      unlock = described_class.op_cat_unlock('hello ', 'world')

      result = BSV::Script::Interpreter.evaluate(unlock, lock)
      expect(result).to be true
    end

    it 'fails when concatenation does not match' do
      lock = described_class.op_cat_lock('hello world')
      unlock = described_class.op_cat_unlock('wrong ', 'data')

      expect { BSV::Script::Interpreter.evaluate(unlock, lock) }.to raise_error(BSV::Script::ScriptError)
    end

    it 'works with empty data items' do
      lock = described_class.op_cat_lock('')
      unlock = described_class.op_cat_unlock('', '')

      result = BSV::Script::Interpreter.evaluate(unlock, lock)
      expect(result).to be true
    end

    it 'works with binary data' do
      binary_data = (0..255).to_a.pack('C*')
      half = binary_data.bytesize / 2
      lock = described_class.op_cat_lock(binary_data)
      unlock = described_class.op_cat_unlock(binary_data[0, half], binary_data[half..])

      result = BSV::Script::Interpreter.evaluate(unlock, lock)
      expect(result).to be true
    end
  end

  describe '#op_cat?' do
    it 'returns true for an OP_CAT puzzle script' do
      script = described_class.op_cat_lock('test')
      expect(script.op_cat?).to be true
    end

    it 'returns false for a P2PKH script' do
      hash160 = BSV::Primitives::Digest.hash160('test key')
      script = described_class.p2pkh_lock(hash160)
      expect(script.op_cat?).to be false
    end

    it 'returns false for an empty script' do
      script = described_class.from_binary('')
      expect(script.op_cat?).to be false
    end
  end
end
