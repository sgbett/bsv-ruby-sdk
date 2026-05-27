# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'BSV::Wallet::Serializer::ListOutputs' do
  subject(:mod) { BSV::Wallet::Serializer::ListOutputs }

  let(:txid_a) { 'ab' * 32 }
  let(:txid_b) { 'cd' * 32 }
  let(:script_hex) { '76a9143cf53c49c322d9d811728182939aee2dca087f9888ac' }
  let(:locking_script) { [script_hex].pack('H*') }

  describe '.serialize_args / .deserialize_args' do
    it 'round-trips full args' do
      args = {
        basket: 'test-basket',
        tags: %w[tag1 tag2],
        tag_query_mode: :any,
        include: :entire_transactions,
        include_custom_instructions: true,
        include_tags: true,
        include_labels: false,
        limit: 100,
        offset: 10,
        seek_permission: true
      }
      expect(mod.deserialize_args(mod.serialize_args(args))).to eq(args)
    end

    it 'round-trips minimal args (basket only)' do
      args = {
        basket: 'minimal-basket',
        tags: nil,
        tag_query_mode: nil,
        include: nil,
        include_custom_instructions: nil,
        include_tags: nil,
        include_labels: nil,
        limit: nil,
        offset: nil,
        seek_permission: nil
      }
      expect(mod.deserialize_args(mod.serialize_args(args))).to eq(args)
    end

    it 'round-trips with tag_query_mode :all' do
      args = { basket: 'x', tags: %w[a b], tag_query_mode: :all, include: nil,
               include_custom_instructions: nil, include_tags: nil, include_labels: nil,
               limit: nil, offset: nil, seek_permission: nil }
      result = mod.deserialize_args(mod.serialize_args(args))
      expect(result[:tag_query_mode]).to eq(:all)
    end

    it 'encodes tag_query_mode :all as byte 1' do
      bytes = mod.serialize_args(basket: 'x', tags: [], tag_query_mode: :all, include: nil,
                                 include_custom_instructions: nil, include_tags: nil,
                                 include_labels: nil, limit: nil, offset: nil, seek_permission: nil)
      r = BSV::Wallet::Wire::Reader.new(bytes)
      r.read_str_with_varint_len  # basket
      r.read_string_slice         # tags
      expect(r.read_byte).to eq(1)
    end

    it 'encodes tag_query_mode :any as byte 2' do
      bytes = mod.serialize_args(basket: 'x', tags: [], tag_query_mode: :any, include: nil,
                                 include_custom_instructions: nil, include_tags: nil,
                                 include_labels: nil, limit: nil, offset: nil, seek_permission: nil)
      r = BSV::Wallet::Wire::Reader.new(bytes)
      r.read_str_with_varint_len
      r.read_string_slice
      expect(r.read_byte).to eq(2)
    end

    it 'encodes nil tag_query_mode as 0xFF' do
      bytes = mod.serialize_args(basket: 'x', tags: nil, tag_query_mode: nil, include: nil,
                                 include_custom_instructions: nil, include_tags: nil,
                                 include_labels: nil, limit: nil, offset: nil, seek_permission: nil)
      r = BSV::Wallet::Wire::Reader.new(bytes)
      r.read_str_with_varint_len
      r.read_string_slice
      expect(r.read_byte).to eq(0xFF)
    end

    it 'round-trips empty tags array' do
      args = { basket: 'x', tags: [], tag_query_mode: nil, include: nil,
               include_custom_instructions: nil, include_tags: nil, include_labels: nil,
               limit: nil, offset: nil, seek_permission: nil }
      result = mod.deserialize_args(mod.serialize_args(args))
      expect(result[:tags]).to eq([])
    end
  end

  describe '.serialize_result / .deserialize_result' do
    it 'round-trips with BEEF and multiple outputs' do
      result = {
        total_outputs: 2,
        beef: "\x01\x02\x03\x04".b,
        outputs: [
          {
            outpoint: "#{txid_a}.0",
            satoshis: 1000,
            locking_script: locking_script,
            custom_instructions: 'instructions',
            tags: ['tag1'],
            labels: ['label1'],
            spendable: true
          },
          {
            outpoint: "#{txid_b}.1",
            satoshis: 2000,
            locking_script: nil,
            custom_instructions: nil,
            tags: nil,
            labels: nil,
            spendable: true
          }
        ]
      }
      decoded = mod.deserialize_result(mod.serialize_result(result))
      expect(decoded[:total_outputs]).to eq(2)
      expect(decoded[:beef]).to eq("\x01\x02\x03\x04".b)
      expect(decoded[:outputs][0][:outpoint]).to eq("#{txid_a}.0")
      expect(decoded[:outputs][0][:satoshis]).to eq(1000)
      expect(decoded[:outputs][1][:outpoint]).to eq("#{txid_b}.1")
    end

    it 'round-trips with no BEEF' do
      result = { total_outputs: 0, beef: nil, outputs: [] }
      decoded = mod.deserialize_result(mod.serialize_result(result))
      expect(decoded[:beef]).to be_nil
      expect(decoded[:outputs]).to eq([])
    end

    it 'round-trips with locking script' do
      result = {
        total_outputs: 1,
        beef: nil,
        outputs: [{
          outpoint: "#{txid_a}.0", satoshis: 500, locking_script: locking_script,
          custom_instructions: nil, tags: nil, labels: nil, spendable: true
        }]
      }
      decoded = mod.deserialize_result(mod.serialize_result(result))
      expect(decoded[:outputs][0][:locking_script]).to eq(locking_script)
    end

    it 'round-trips with custom_instructions' do
      result = {
        total_outputs: 1,
        beef: nil,
        outputs: [{
          outpoint: "#{txid_a}.0", satoshis: 100, locking_script: nil,
          custom_instructions: 'my-custom', tags: nil, labels: nil, spendable: true
        }]
      }
      decoded = mod.deserialize_result(mod.serialize_result(result))
      expect(decoded[:outputs][0][:custom_instructions]).to eq('my-custom')
    end
  end
end
