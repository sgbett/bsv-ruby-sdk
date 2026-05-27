# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/MultipleDescribes

SIGN_TXID1 = '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
SIGN_TXID2 = 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef'

RSpec.describe 'BSV::Wallet::Serializer::SignActionArgs' do
  let(:mod) { BSV::Wallet::Serializer::SignActionArgs }

  describe 'minimal args round-trip' do
    it 'round-trips single spend with no options' do
      args = { spends: { 0 => { unlocking_script: "\x00".b } } }
      result = mod.deserialize(mod.serialize(args))
      expect(result[:spends][0][:unlocking_script]).to eq("\x00".b)
    end
  end

  describe 'full args round-trip' do
    let(:args) do
      {
        spends: {
          0 => { unlocking_script: "\xab\xcd\xef".b, sequence_number: 123 },
          1 => { unlocking_script: "\xde\xad\xbe\xef".b, sequence_number: 456 }
        },
        reference: 'ref123'.b,
        options: {
          accept_delayed_broadcast: true,
          return_txid_only: false,
          no_send: true,
          send_with: [SIGN_TXID1, SIGN_TXID2]
        }
      }
    end

    it 'round-trips all fields' do
      bytes  = mod.serialize(args)
      result = mod.deserialize(bytes)
      expect(result[:spends][0][:unlocking_script]).to eq("\xab\xcd\xef".b)
      expect(result[:spends][0][:sequence_number]).to eq(123)
      expect(result[:spends][1][:unlocking_script]).to eq("\xde\xad\xbe\xef".b)
      expect(result[:spends][1][:sequence_number]).to eq(456)
      expect(result[:reference]).to eq('ref123'.b)
      expect(result[:options][:accept_delayed_broadcast]).to be(true)
      expect(result[:options][:return_txid_only]).to be(false)
      expect(result[:options][:no_send]).to be(true)
      expect(result[:options][:send_with]).to eq([SIGN_TXID1, SIGN_TXID2])
    end

    it 'serialises spends in index-sorted order' do
      args_unordered = {
        spends: {
          2 => { unlocking_script: "\x03".b },
          0 => { unlocking_script: "\x01".b },
          1 => { unlocking_script: "\x02".b }
        }
      }
      bytes  = mod.serialize(args_unordered)
      result = mod.deserialize(bytes)
      expect(result[:spends].keys.sort).to eq([0, 1, 2])
    end
  end

  describe 'multiple spends' do
    it 'round-trips multiple spends with sequence numbers' do
      args = {
        spends: {
          0 => { unlocking_script: "\xab\xcd\xef".b, sequence_number: 123 },
          1 => { unlocking_script: "\xde\xad\xbe\xef".b, sequence_number: 456 }
        }
      }
      result = mod.deserialize(mod.serialize(args))
      expect(result[:spends].length).to eq(2)
      expect(result[:spends][0][:sequence_number]).to eq(123)
      expect(result[:spends][1][:sequence_number]).to eq(456)
    end
  end

  describe 'no options' do
    it 'absent options round-trips as nil' do
      args   = { spends: { 0 => { unlocking_script: "\x01".b } } }
      result = mod.deserialize(mod.serialize(args))
      expect(result[:options]).to be_nil
    end
  end
end

RSpec.describe 'BSV::Wallet::Serializer::SignActionResult' do
  let(:mod) { BSV::Wallet::Serializer::SignActionResult }

  describe 'minimal result round-trip' do
    it 'round-trips empty result' do
      bytes  = mod.serialize({})
      result = mod.deserialize(bytes)
      expect(result[:txid]).to be_nil
      expect(result[:tx]).to be_nil
    end
  end

  describe 'full result round-trip' do
    let(:result_hash) do
      {
        txid: SIGN_TXID1,
        tx: "\x01\x02\x03".b,
        send_with_results: [
          { txid: SIGN_TXID2, status: :unproven }
        ]
      }
    end

    it 'round-trips all fields' do
      bytes  = mod.serialize(result_hash)
      result = mod.deserialize(bytes)
      expect(result[:txid]).to eq(SIGN_TXID1)
      expect(result[:tx]).to eq("\x01\x02\x03".b)
      expect(result[:send_with_results][0][:status]).to eq(:unproven)
    end
  end
end

# rubocop:enable RSpec/MultipleDescribes
