# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Transaction::TransactionOutput do
  let(:p2pkh_hash) { ['751e76e8199196d454941c45d1b3a323f1433bd6'].pack('H*') }
  let(:locking_script) { BSV::Script::Script.p2pkh_lock(p2pkh_hash) }

  describe '#to_binary' do
    it 'serialises satoshis as 8-byte LE followed by varint script length and script' do
      output = described_class.new(satoshis: 50_000, locking_script: locking_script)
      binary = output.to_binary

      # 8 bytes satoshis + 1 byte varint (25) + 25 bytes script = 34
      expect(binary.bytesize).to eq(34)
      expect(binary.byteslice(0, 8).unpack1('Q<')).to eq(50_000)
      expect(binary.getbyte(8)).to eq(25)
      expect(binary.byteslice(9, 25)).to eq(locking_script.to_binary)
    end
  end

  describe '.from_binary' do
    it 'deserialises from binary' do
      output = described_class.new(satoshis: 100_000_000, locking_script: locking_script)
      binary = output.to_binary

      parsed, bytes_consumed = described_class.from_binary(binary)

      expect(parsed.satoshis).to eq(100_000_000)
      expect(parsed.locking_script.to_hex).to eq(locking_script.to_hex)
      expect(bytes_consumed).to eq(binary.bytesize)
    end

    it 'handles an offset' do
      output = described_class.new(satoshis: 1000, locking_script: locking_script)
      padding = "\x00".b * 5
      data = padding + output.to_binary

      parsed, bytes_consumed = described_class.from_binary(data, 5)
      expect(parsed.satoshis).to eq(1000)
      expect(bytes_consumed).to eq(output.to_binary.bytesize)
    end
  end

  describe '#locking_script=' do
    it 'allows the locking script to be mutated after construction' do
      output = described_class.new(satoshis: 1000, locking_script: locking_script)
      new_script = BSV::Script::Script.op_return('data'.b)

      output.locking_script = new_script
      expect(output.locking_script.to_hex).to eq(new_script.to_hex)
    end

    it 'reflects the new locking script in to_binary' do
      output = described_class.new(satoshis: 1000, locking_script: locking_script)
      new_script = BSV::Script::Script.op_return('data'.b)
      output.locking_script = new_script

      binary = output.to_binary
      parsed, = described_class.from_binary(binary)
      expect(parsed.locking_script.to_hex).to eq(new_script.to_hex)
    end
  end

  describe 'round-trip' do
    it 'serialises and deserialises an OP_RETURN output' do
      script = BSV::Script::Script.op_return('hello world'.b)
      output = described_class.new(satoshis: 0, locking_script: script)
      binary = output.to_binary

      parsed, = described_class.from_binary(binary)
      expect(parsed.satoshis).to eq(0)
      expect(parsed.locking_script.to_hex).to eq(script.to_hex)
    end
  end
end
