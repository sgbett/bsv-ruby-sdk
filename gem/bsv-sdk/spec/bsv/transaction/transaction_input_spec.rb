# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Transaction::TransactionInput do
  let(:txid_hex) { 'a477af6b2667c29670467e4e0728b685ee07b240235771862318e29ddbe58458' }
  let(:txid_internal) { described_class.txid_from_hex(txid_hex) }

  describe '.txid_from_hex' do
    it 'converts display-order hex to internal byte order (reversed)' do
      expect(txid_internal.bytesize).to eq(32)
      expect(txid_internal.unpack1('H*')).to eq('5884e5db9de218238671572340b207ee85b628074e7e467096c267266baf77a4')
    end
  end

  describe '#txid_hex' do
    it 'returns the display-order hex of the previous txid' do
      input = described_class.new(prev_tx_id: txid_internal, prev_tx_out_index: 0)
      expect(input.txid_hex).to eq(txid_hex)
    end
  end

  describe '#to_binary' do
    it 'serialises an unsigned input (empty script)' do
      input = described_class.new(prev_tx_id: txid_internal, prev_tx_out_index: 1)
      binary = input.to_binary

      # 32 txid + 4 vout + 1 varint(0) + 0 script + 4 sequence = 41
      expect(binary.bytesize).to eq(41)
      expect(binary.byteslice(0, 32)).to eq(txid_internal)
      expect(binary.byteslice(32, 4).unpack1('V')).to eq(1)
      expect(binary.getbyte(36)).to eq(0)
      expect(binary.byteslice(37, 4).unpack1('V')).to eq(0xFFFFFFFF)
    end

    it 'serialises an input with an unlocking script' do
      script = BSV::Script::Script.from_hex('0102')
      input = described_class.new(
        prev_tx_id: txid_internal,
        prev_tx_out_index: 0,
        unlocking_script: script
      )
      binary = input.to_binary

      # 32 + 4 + 1 + 2 + 4 = 43
      expect(binary.bytesize).to eq(43)
      expect(binary.getbyte(36)).to eq(2)
    end
  end

  describe '.from_binary' do
    it 'deserialises and round-trips' do
      input = described_class.new(
        prev_tx_id: txid_internal,
        prev_tx_out_index: 3,
        sequence: 0xFFFFFFFE
      )
      binary = input.to_binary

      parsed, bytes_consumed = described_class.from_binary(binary)
      expect(parsed.prev_tx_id).to eq(txid_internal)
      expect(parsed.prev_tx_out_index).to eq(3)
      expect(parsed.unlocking_script).to be_nil
      expect(parsed.sequence).to eq(0xFFFFFFFE)
      expect(bytes_consumed).to eq(binary.bytesize)
    end

    it 'parses from an offset' do
      input = described_class.new(prev_tx_id: txid_internal, prev_tx_out_index: 0)
      padding = "\xFF".b * 10
      data = padding + input.to_binary

      parsed, = described_class.from_binary(data, 10)
      expect(parsed.txid_hex).to eq(txid_hex)
    end
  end

  describe '#sequence=' do
    it 'allows the sequence to be mutated after construction' do
      input = described_class.new(prev_tx_id: txid_internal, prev_tx_out_index: 0)
      expect(input.sequence).to eq(0xFFFFFFFF)

      input.sequence = 0x00000001
      expect(input.sequence).to eq(0x00000001)
    end

    it 'reflects the new sequence in to_binary' do
      input = described_class.new(prev_tx_id: txid_internal, prev_tx_out_index: 0)
      input.sequence = 0x00000001

      binary = input.to_binary
      expect(binary.byteslice(37, 4).unpack1('V')).to eq(0x00000001)
    end

    it 'serialises correctly when mutated from 0xFFFFFFFF to 0' do
      input = described_class.new(prev_tx_id: txid_internal, prev_tx_out_index: 0, sequence: 0xFFFFFFFF)
      input.sequence = 0

      binary = input.to_binary
      expect(binary.byteslice(37, 4).unpack1('V')).to eq(0)

      parsed, = described_class.from_binary(binary)
      expect(parsed.sequence).to eq(0)
    end
  end

  describe '#outpoint_binary' do
    it 'returns 36-byte outpoint (txid + vout)' do
      input = described_class.new(prev_tx_id: txid_internal, prev_tx_out_index: 2)
      outpoint = input.outpoint_binary

      expect(outpoint.bytesize).to eq(36)
      expect(outpoint.byteslice(0, 32)).to eq(txid_internal)
      expect(outpoint.byteslice(32, 4).unpack1('V')).to eq(2)
    end
  end
end
