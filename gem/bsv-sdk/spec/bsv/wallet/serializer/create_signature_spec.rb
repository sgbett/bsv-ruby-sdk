# frozen_string_literal: true

CSIG_HASH_32 = ("\xAB" * 32).b

RSpec.describe 'BSV::Wallet::Serializer::CreateSignature' do
  subject(:mod) { BSV::Wallet::Serializer::CreateSignature }

  def round_trip_args(args)
    bytes = mod::Args.serialize(args)
    mod::Args.deserialize(bytes)
  end

  describe 'Args — data path' do
    it 'round-trips with data' do
      args = {
        protocol_id: [2, 'hello world'],
        key_id: '1',
        counterparty: 'self',
        data: "\x01\x02\x03".b
      }
      result = round_trip_args(args)
      expect(result[:data]).to eq("\x01\x02\x03".b)
      expect(result[:hash_to_directly_sign]).to be_nil
    end

    it 'round-trips empty data' do
      args = { protocol_id: [2, 'hello world'], key_id: '1', counterparty: 'self', data: ''.b }
      result = round_trip_args(args)
      expect(result[:data]).to eq(''.b)
    end
  end

  describe 'Args — hash path' do
    it 'round-trips with hash_to_directly_sign' do
      args = {
        protocol_id: [2, 'hello world'],
        key_id: '1',
        counterparty: 'self',
        hash_to_directly_sign: CSIG_HASH_32
      }
      result = round_trip_args(args)
      expect(result[:hash_to_directly_sign]).to eq(CSIG_HASH_32)
      expect(result[:data]).to be_nil
    end
  end

  describe 'Args — validation' do
    it 'raises WERR_INVALID_PARAMETER when both data and hash provided' do
      args = {
        protocol_id: [2, 'hello world'],
        key_id: '1',
        counterparty: 'self',
        data: "\x01".b,
        hash_to_directly_sign: CSIG_HASH_32
      }
      expect { mod::Args.serialize(args) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises WERR_INVALID_PARAMETER when neither data nor hash provided' do
      args = { protocol_id: [2, 'hello world'], key_id: '1', counterparty: 'self' }
      expect { mod::Args.serialize(args) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  describe 'Result' do
    it 'round-trips DER signature bytes' do
      der = "0D #{"\xAA" * 32} #{"\xBB" * 32}"
      result = { signature: der.b }
      bytes = mod::Result.serialize(result)
      back = mod::Result.deserialize(bytes)
      expect(back[:signature]).to eq(der.b)
    end

    it 'round-trips empty signature' do
      bytes = mod::Result.serialize({ signature: ''.b })
      back = mod::Result.deserialize(bytes)
      expect(back[:signature]).to eq(''.b)
    end
  end
end
