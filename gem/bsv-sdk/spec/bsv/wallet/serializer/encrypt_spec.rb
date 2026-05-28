# frozen_string_literal: true

RSpec.describe 'BSV::Wallet::Serializer::Encrypt' do
  subject(:mod) { BSV::Wallet::Serializer::Encrypt }

  let(:pubkey_hex) { '0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798' }

  def round_trip_args(args)
    bytes = mod::Args.serialize(args)
    mod::Args.deserialize(bytes)
  end

  describe 'Args' do
    it 'round-trips empty plaintext with self counterparty' do
      args = { protocol_id: [2, 'hello world'], key_id: '1', counterparty: 'self', plaintext: ''.b }
      result = round_trip_args(args)
      expect(result[:plaintext]).to eq(''.b)
      expect(result[:counterparty]).to eq('self')
      expect(result[:protocol_id]).to eq([2, 'hello world'])
      expect(result[:key_id]).to eq('1')
    end

    it 'round-trips non-empty plaintext' do
      args = {
        protocol_id: [2, 'hello world'],
        key_id: '1',
        counterparty: 'self',
        plaintext: "\x01\x02\x03\x04".b
      }
      result = round_trip_args(args)
      expect(result[:plaintext]).to eq("\x01\x02\x03\x04".b)
    end

    it 'round-trips with anyone counterparty' do
      args = { protocol_id: [0, 'bsv protocol'], key_id: 'my-key', counterparty: 'anyone', plaintext: ''.b }
      result = round_trip_args(args)
      expect(result[:counterparty]).to eq('anyone')
    end

    it 'round-trips with specific pubkey counterparty' do
      args = { protocol_id: [1, 'test proto'], key_id: 'k', counterparty: pubkey_hex, plaintext: "\xAB".b }
      result = round_trip_args(args)
      expect(result[:counterparty]).to eq(pubkey_hex)
    end

    it 'round-trips security level 0' do
      args = { protocol_id: [0, 'minimal protocol'], key_id: 'min-key', counterparty: 'self', plaintext: "\x05\x06".b }
      result = round_trip_args(args)
      expect(result[:protocol_id]).to eq([0, 'minimal protocol'])
    end

    it 'round-trips security level 1' do
      args = { protocol_id: [1, 'some protocol'], key_id: 'k2', counterparty: 'self', plaintext: ''.b }
      result = round_trip_args(args)
      expect(result[:protocol_id]).to eq([1, 'some protocol'])
    end

    it 'round-trips privileged params' do
      args = {
        protocol_id: [2, 'hello world'],
        key_id: '1',
        counterparty: 'self',
        plaintext: ''.b,
        privileged: true,
        privileged_reason: 'test reason'
      }
      result = round_trip_args(args)
      expect(result[:privileged]).to be(true)
      expect(result[:privileged_reason]).to eq('test reason')
    end

    it 'round-trips nil privileged_reason as nil' do
      args = { protocol_id: [2, 'hello world'], key_id: '1', counterparty: 'self', plaintext: ''.b }
      result = round_trip_args(args)
      expect(result[:privileged_reason]).to be_nil
    end

    it 'round-trips seek_permission' do
      args = { protocol_id: [2, 'hello world'], key_id: '1', counterparty: 'self', plaintext: ''.b, seek_permission: true }
      result = round_trip_args(args)
      expect(result[:seek_permission]).to be(true)
    end

    it 'round-trips seek_permission=false' do
      args = { protocol_id: [2, 'hello world'], key_id: '1', counterparty: 'self', plaintext: ''.b, seek_permission: false }
      result = round_trip_args(args)
      expect(result[:seek_permission]).to be(false)
    end

    it 'round-trips 100-byte plaintext' do
      plaintext = ("\xAA" * 100).b
      args = { protocol_id: [2, 'hello world'], key_id: '1', counterparty: 'self', plaintext: plaintext }
      result = round_trip_args(args)
      expect(result[:plaintext]).to eq(plaintext)
    end
  end

  describe 'Result' do
    it 'round-trips ciphertext bytes' do
      result = { ciphertext: "\xDE\xAD\xBE\xEF".b }
      bytes = mod::Result.serialize(result)
      back = mod::Result.deserialize(bytes)
      expect(back[:ciphertext]).to eq("\xDE\xAD\xBE\xEF".b)
    end

    it 'round-trips empty ciphertext' do
      result = { ciphertext: ''.b }
      bytes = mod::Result.serialize(result)
      back = mod::Result.deserialize(bytes)
      expect(back[:ciphertext]).to eq(''.b)
    end
  end
end
