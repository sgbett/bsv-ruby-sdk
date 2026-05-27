# frozen_string_literal: true

RSpec.describe 'BSV::Wallet::Serializer::Decrypt' do
  subject(:mod) { BSV::Wallet::Serializer::Decrypt }

  def round_trip_args(args)
    bytes = mod::Args.serialize(args)
    mod::Args.deserialize(bytes)
  end

  describe 'Args' do
    it 'round-trips empty ciphertext with self counterparty' do
      args = { protocol_id: [2, 'hello world'], key_id: '1', counterparty: 'self', ciphertext: ''.b }
      result = round_trip_args(args)
      expect(result[:ciphertext]).to eq(''.b)
      expect(result[:counterparty]).to eq('self')
    end

    it 'round-trips non-empty ciphertext' do
      args = { protocol_id: [2, 'hello world'], key_id: '1', counterparty: 'self', ciphertext: "\x0A\x0B\x0C".b }
      result = round_trip_args(args)
      expect(result[:ciphertext]).to eq("\x0A\x0B\x0C".b)
    end

    it 'round-trips with anyone counterparty' do
      args = { protocol_id: [0, 'bsv protocol'], key_id: 'k', counterparty: 'anyone', ciphertext: ''.b }
      result = round_trip_args(args)
      expect(result[:counterparty]).to eq('anyone')
    end

    it 'raises WERR_INVALID_PARAMETER for invalid counterparty' do
      args = { protocol_id: [2, 'hello world'], key_id: '1', counterparty: 'invalid', ciphertext: ''.b }
      expect { mod::Args.serialize(args) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  describe 'Result' do
    it 'round-trips plaintext bytes' do
      result = { plaintext: "\x01\x02\x03".b }
      bytes = mod::Result.serialize(result)
      back = mod::Result.deserialize(bytes)
      expect(back[:plaintext]).to eq("\x01\x02\x03".b)
    end

    it 'round-trips empty plaintext' do
      result = { plaintext: ''.b }
      bytes = mod::Result.serialize(result)
      back = mod::Result.deserialize(bytes)
      expect(back[:plaintext]).to eq(''.b)
    end
  end
end
