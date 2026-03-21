# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe BSV::X402::NonceUTXO do
  let(:valid_attrs) do
    {
      txid: 'abcd1234' * 8,
      vout: 0,
      satoshis: 1,
      locking_script_hex: "76a914#{'00' * 20}88ac"
    }
  end

  describe '.new' do
    it 'constructs with valid attributes' do
      utxo = described_class.new(**valid_attrs)
      expect(utxo.txid).to eq(valid_attrs[:txid])
      expect(utxo.vout).to eq(0)
      expect(utxo.satoshis).to eq(1)
      expect(utxo.locking_script_hex).to eq(valid_attrs[:locking_script_hex])
    end

    it 'is frozen after construction' do
      expect(described_class.new(**valid_attrs)).to be_frozen
    end

    it 'raises ValidationError when satoshis is zero' do
      expect { described_class.new(**valid_attrs, satoshis: 0) }
        .to raise_error(BSV::X402::ValidationError, /satoshis must be greater than zero/)
    end

    it 'raises ValidationError when satoshis is negative' do
      expect { described_class.new(**valid_attrs, satoshis: -1) }
        .to raise_error(BSV::X402::ValidationError, /satoshis must be greater than zero/)
    end

    it 'raises ValidationError when satoshis is not an integer' do
      expect { described_class.new(**valid_attrs, satoshis: '1') }
        .to raise_error(BSV::X402::ValidationError)
    end
  end

  describe '.from_hash' do
    it 'constructs from a string-keyed hash' do
      hash = {
        'txid' => valid_attrs[:txid],
        'vout' => valid_attrs[:vout],
        'satoshis' => valid_attrs[:satoshis],
        'locking_script_hex' => valid_attrs[:locking_script_hex]
      }
      utxo = described_class.from_hash(hash)
      expect(utxo.txid).to eq(valid_attrs[:txid])
    end

    it 'constructs from a symbol-keyed hash' do
      utxo = described_class.from_hash(valid_attrs)
      expect(utxo.satoshis).to eq(1)
    end

    it 'raises ValidationError for a missing field' do
      attrs_without_txid = valid_attrs.reject { |k, _| k == :txid }
      expect { described_class.from_hash(attrs_without_txid) }
        .to raise_error(BSV::X402::ValidationError, /txid/)
    end
  end

  describe '#to_hash' do
    it 'returns a hash with string keys' do
      utxo = described_class.new(**valid_attrs)
      hash = utxo.to_hash
      expect(hash.keys).to all(be_a(String))
    end

    it 'includes all four fields' do
      utxo = described_class.new(**valid_attrs)
      hash = utxo.to_hash
      expect(hash.keys).to contain_exactly('txid', 'vout', 'satoshis', 'locking_script_hex')
    end

    it 'round-trips through from_hash' do
      original = described_class.new(**valid_attrs)
      restored = described_class.from_hash(original.to_hash)
      expect(restored.txid).to eq(original.txid)
      expect(restored.satoshis).to eq(original.satoshis)
    end
  end
end
