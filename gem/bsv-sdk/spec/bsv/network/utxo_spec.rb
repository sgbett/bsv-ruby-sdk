# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Network::UTXO do
  subject(:utxo) do
    described_class.new(tx_hash: 'abcd1234', tx_pos: 0, satoshis: 50_000, height: 800_000)
  end

  describe '#initialize' do
    it 'stores all attributes' do
      expect(utxo.tx_hash).to eq('abcd1234')
      expect(utxo.tx_pos).to eq(0)
      expect(utxo.satoshis).to eq(50_000)
      expect(utxo.height).to eq(800_000)
    end

    it 'defaults height to nil' do
      u = described_class.new(tx_hash: 'abcd1234', tx_pos: 0, satoshis: 1000)
      expect(u.height).to be_nil
    end
  end

  describe '#==' do
    it 'considers UTXOs with the same outpoint equal' do
      other = described_class.new(tx_hash: 'abcd1234', tx_pos: 0, satoshis: 99_999, height: 1)
      expect(utxo).to eq(other)
    end

    it 'considers UTXOs with different tx_hash unequal' do
      other = described_class.new(tx_hash: 'different', tx_pos: 0, satoshis: 50_000)
      expect(utxo).not_to eq(other)
    end

    it 'considers UTXOs with different tx_pos unequal' do
      other = described_class.new(tx_hash: 'abcd1234', tx_pos: 1, satoshis: 50_000)
      expect(utxo).not_to eq(other)
    end

    it 'returns false for non-UTXO objects' do
      expect(utxo).not_to eq('not a utxo')
    end
  end

  describe '#hash' do
    it 'is consistent with ==' do
      other = described_class.new(tx_hash: 'abcd1234', tx_pos: 0, satoshis: 99_999)
      expect(utxo.hash).to eq(other.hash)
    end

    it 'differs for different outpoints' do
      other = described_class.new(tx_hash: 'abcd1234', tx_pos: 1, satoshis: 50_000)
      expect(utxo.hash).not_to eq(other.hash)
    end

    it 'works correctly as a Hash key' do
      other = described_class.new(tx_hash: 'abcd1234', tx_pos: 0, satoshis: 99_999)
      h = { utxo => 'found' }
      expect(h[other]).to eq('found')
    end
  end

  describe 'read-only attributes' do
    it 'does not allow setting attributes' do
      expect(utxo).not_to respond_to(:tx_hash=)
      expect(utxo).not_to respond_to(:tx_pos=)
      expect(utxo).not_to respond_to(:satoshis=)
      expect(utxo).not_to respond_to(:height=)
    end
  end
end
