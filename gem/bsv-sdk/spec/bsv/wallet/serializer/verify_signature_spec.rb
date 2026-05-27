# frozen_string_literal: true

VSIG_HASH = ("\xCC" * 32).b
VSIG_DER  = "0D #{"\xAA" * 32} #{"\xBB" * 32}".b

RSpec.describe 'BSV::Wallet::Serializer::VerifySignature' do
  subject(:mod) { BSV::Wallet::Serializer::VerifySignature }

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
        signature: VSIG_DER,
        data: "\x01\x02".b
      }
      result = round_trip_args(args)
      expect(result[:data]).to eq("\x01\x02".b)
      expect(result[:signature]).to eq(VSIG_DER)
    end
  end

  describe 'Args — hash path' do
    it 'round-trips with hash_to_directly_verify' do
      args = {
        protocol_id: [2, 'hello world'],
        key_id: '1',
        counterparty: 'self',
        signature: VSIG_DER,
        hash_to_directly_verify: VSIG_HASH
      }
      result = round_trip_args(args)
      expect(result[:hash_to_directly_verify]).to eq(VSIG_HASH)
      expect(result[:data]).to be_nil
    end
  end

  describe 'Args — for_self flag' do
    it 'round-trips for_self=true' do
      args = {
        protocol_id: [2, 'hello world'],
        key_id: '1',
        counterparty: 'self',
        signature: VSIG_DER,
        data: ''.b,
        for_self: true
      }
      result = round_trip_args(args)
      expect(result[:for_self]).to be(true)
    end

    it 'round-trips for_self=nil' do
      args = {
        protocol_id: [2, 'hello world'],
        key_id: '1',
        counterparty: 'self',
        signature: VSIG_DER,
        data: ''.b
      }
      result = round_trip_args(args)
      expect(result[:for_self]).to be_nil
    end
  end

  describe 'Args — validation' do
    it 'raises WERR_INVALID_PARAMETER when both data and hash provided' do
      args = {
        protocol_id: [2, 'hello world'],
        key_id: '1',
        counterparty: 'self',
        signature: VSIG_DER,
        data: "\x01".b,
        hash_to_directly_verify: VSIG_HASH
      }
      expect { mod::Args.serialize(args) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises WERR_INVALID_PARAMETER when neither data nor hash provided' do
      args = { protocol_id: [2, 'hello world'], key_id: '1', counterparty: 'self', signature: VSIG_DER }
      expect { mod::Args.serialize(args) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises WERR_INVALID_PARAMETER when signature is nil' do
      args = { protocol_id: [2, 'hello world'], key_id: '1', counterparty: 'self', data: ''.b }
      expect { mod::Args.serialize(args) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  describe 'Result' do
    it 'deserialises to valid: true' do
      expect(mod::Result.deserialize(''.b)).to eq({ valid: true })
    end

    it 'serialises to empty bytes' do
      expect(mod::Result.serialize({ valid: true })).to eq(''.b)
    end
  end
end
