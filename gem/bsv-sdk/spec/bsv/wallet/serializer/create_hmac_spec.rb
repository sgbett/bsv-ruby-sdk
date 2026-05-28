# frozen_string_literal: true

CHMAC_32 = ("\xAB" * 32).b

RSpec.describe 'BSV::Wallet::Serializer::CreateHmac' do
  subject(:mod) { BSV::Wallet::Serializer::CreateHmac }

  def round_trip_args(args)
    bytes = mod::Args.serialize(args)
    mod::Args.deserialize(bytes)
  end

  describe 'Args' do
    it 'round-trips empty data' do
      args = { protocol_id: [2, 'hello world'], key_id: '1', counterparty: 'self', data: ''.b }
      result = round_trip_args(args)
      expect(result[:data]).to eq(''.b)
      expect(result[:protocol_id]).to eq([2, 'hello world'])
    end

    it 'round-trips non-empty data' do
      args = { protocol_id: [1, 'test proto'], key_id: 'k', counterparty: 'self', data: "\xFF\x00".b }
      result = round_trip_args(args)
      expect(result[:data]).to eq("\xFF\x00".b)
    end

    it 'correctly varint-encodes large data lengths' do
      large_data = ('x' * 200).b
      args = { protocol_id: [2, 'hello world'], key_id: '1', counterparty: 'self', data: large_data }
      result = round_trip_args(args)
      expect(result[:data].bytesize).to eq(200)
    end
  end

  describe 'Result' do
    it 'round-trips a 32-byte HMAC' do
      result = { hmac: CHMAC_32 }
      bytes = mod::Result.serialize(result)
      back = mod::Result.deserialize(bytes)
      expect(back[:hmac]).to eq(CHMAC_32)
    end

    it 'raises ArgumentError when HMAC is not 32 bytes' do
      result = { hmac: "\x00" * 16 }
      expect { mod::Result.serialize(result) }.to raise_error(ArgumentError, /32 bytes/)
    end

    it 'raises ArgumentError when deserializing fewer than 32 bytes' do
      expect { mod::Result.deserialize("\x00" * 10) }.to raise_error(ArgumentError)
    end
  end
end
