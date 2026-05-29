# frozen_string_literal: true

VHMAC_32 = ("\xAB" * 32).b

RSpec.describe 'BSV::Wallet::Serializer::VerifyHmac' do
  subject(:mod) { BSV::Wallet::Serializer::VerifyHmac }

  def round_trip_args(args)
    bytes = mod::Args.serialize(args)
    mod::Args.deserialize(bytes)
  end

  describe 'Args' do
    let(:valid_args) do
      {
        protocol_id: [2, 'hello world'],
        key_id: '1',
        counterparty: 'self',
        hmac: VHMAC_32,
        data: "\x01\x02".b
      }
    end

    it 'round-trips HMAC and data' do
      result = round_trip_args(valid_args)
      expect(result[:hmac]).to eq(VHMAC_32)
      expect(result[:data]).to eq("\x01\x02".b)
    end

    it 'round-trips empty data' do
      args = valid_args.merge(data: ''.b)
      result = round_trip_args(args)
      expect(result[:data]).to eq(''.b)
      expect(result[:hmac]).to eq(VHMAC_32)
    end

    it 'raises WERR_INVALID_PARAMETER when HMAC is not 32 bytes' do
      args = valid_args.merge(hmac: "\x00" * 16)
      expect { mod::Args.serialize(args) }.to raise_error(BSV::Wallet::InvalidParameterError, /32 bytes/)
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
