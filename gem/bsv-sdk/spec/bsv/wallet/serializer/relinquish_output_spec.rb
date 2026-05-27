# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'BSV::Wallet::Serializer::RelinquishOutput' do
  subject(:mod) { BSV::Wallet::Serializer::RelinquishOutput }

  let(:txid) { 'ab' * 32 }

  describe '.serialize_args / .deserialize_args' do
    it 'round-trips basket and outpoint' do
      args = { basket: 'default', output: "#{txid}.0" }
      expect(mod.deserialize_args(mod.serialize_args(args))).to eq(args)
    end

    it 'round-trips a non-zero vout' do
      args = { basket: 'custom', output: "#{txid}.42" }
      result = mod.deserialize_args(mod.serialize_args(args))
      expect(result[:output]).to eq("#{txid}.42")
    end

    it 'rejects an invalid outpoint with InvalidParameterError' do
      expect do
        mod.serialize_args(basket: 'x', output: 'not-an-outpoint')
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'encodes basket as varint-prefixed string followed by 36-byte outpoint' do
      bytes = mod.serialize_args(basket: 'abc', output: "#{txid}.0")
      r = BSV::Wallet::Wire::Reader.new(bytes)
      expect(r.read_str_with_varint_len).to eq('abc')
      outpoint = r.read_outpoint
      expect(outpoint[:txid_hex]).to eq(txid)
      expect(outpoint[:vout]).to eq(0)
      expect(r.remaining).to eq(0)
    end
  end

  describe '.serialize_result / .deserialize_result' do
    it 'serialises result to empty bytes' do
      expect(mod.serialize_result({ relinquished: true })).to eq(''.b)
    end

    it 'deserialises to { relinquished: true }' do
      expect(mod.deserialize_result(''.b)).to eq({ relinquished: true })
    end
  end
end
