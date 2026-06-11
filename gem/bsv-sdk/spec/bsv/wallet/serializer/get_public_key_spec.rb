# frozen_string_literal: true

GPK_PUBKEY_33 = "\x02#{"\xAB" * 32}".b

RSpec.describe 'BSV::Wallet::Serializer::GetPublicKey' do
  subject(:mod) { BSV::Wallet::Serializer::GetPublicKey }

  def round_trip_args(args)
    bytes = mod::Args.serialize(args)
    mod::Args.deserialize(bytes)
  end

  describe 'Args — identity_key=true short-circuit' do
    it 'round-trips with identity_key=true, ignoring protocol/key_id' do
      args = { identity_key: true, privileged: true, privileged_reason: 'admin' }
      result = round_trip_args(args)
      expect(result[:identity_key]).to be(true)
      expect(result[:privileged]).to be(true)
      expect(result[:privileged_reason]).to eq('admin')
      expect(result[:protocol_id]).to be_nil
    end

    it 'round-trips identity_key=true with no privileged_reason' do
      args = { identity_key: true }
      result = round_trip_args(args)
      expect(result[:identity_key]).to be(true)
      expect(result[:privileged_reason]).to be_nil
    end
  end

  describe 'Args — identity_key=false' do
    it 'round-trips full key-related params' do
      args = {
        identity_key: false,
        protocol_id: [2, 'hello world'],
        key_id: '1',
        counterparty: 'self'
      }
      result = round_trip_args(args)
      expect(result[:identity_key]).to be(false)
      expect(result[:protocol_id]).to eq([2, 'hello world'])
      expect(result[:key_id]).to eq('1')
      expect(result[:counterparty]).to eq('self')
    end

    it 'round-trips for_self flag' do
      args = {
        identity_key: false,
        protocol_id: [1, 'test proto'],
        key_id: 'k',
        counterparty: 'anyone',
        for_self: true
      }
      result = round_trip_args(args)
      expect(result[:for_self]).to be(true)
    end
  end

  describe 'Result' do
    it 'round-trips a 33-byte compressed pubkey' do
      result = { public_key: GPK_PUBKEY_33 }
      bytes = mod::Result.serialize(result)
      back = mod::Result.deserialize(bytes)
      # ADR-001: pubkey returned as 66-char hex on the Ruby side;
      # wire bytes remain 33-byte compressed binary.
      expect(back[:public_key]).to eq(GPK_PUBKEY_33.unpack1('H*'))
    end

    it 'raises ArgumentError when result is too short' do
      expect { mod::Result.deserialize("\x02" * 10) }.to raise_error(ArgumentError)
    end
  end
end
