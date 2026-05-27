# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'BSV::Wallet::Serializer::AbortAction' do
  subject(:mod) { BSV::Wallet::Serializer::AbortAction }

  describe '.serialize_args / .deserialize_args' do
    it 'round-trips a reference payload' do
      args = { reference: "\x01\x02\x03".b }
      expect(mod.deserialize_args(mod.serialize_args(args))).to eq(args)
    end

    it 'round-trips a longer reference' do
      args = { reference: 'x' * 64 }
      expect(mod.deserialize_args(mod.serialize_args(args))).to eq(args)
    end

    it 'round-trips a nil reference as nil' do
      result = mod.deserialize_args(mod.serialize_args(reference: nil))
      expect(result[:reference]).to be_nil
    end

    it 'round-trips an empty reference as nil' do
      result = mod.deserialize_args(mod.serialize_args(reference: ''))
      expect(result[:reference]).to be_nil
    end

    it 'serialises to the raw reference bytes (Go vector: [1,2,3])' do
      bytes = mod.serialize_args(reference: "\x01\x02\x03".b)
      expect(bytes).to eq("\x01\x02\x03".b)
    end
  end

  describe '.serialize_result / .deserialize_result' do
    it 'serialises result to empty bytes' do
      expect(mod.serialize_result({ aborted: true })).to eq(''.b)
    end

    it 'deserialises any bytes to { aborted: true }' do
      expect(mod.deserialize_result(''.b)).to eq({ aborted: true })
    end
  end
end
