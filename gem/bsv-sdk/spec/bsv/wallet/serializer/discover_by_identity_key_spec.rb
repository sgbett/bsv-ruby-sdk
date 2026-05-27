# frozen_string_literal: true

require 'spec_helper'
require 'base64'

DBIK_TXID         = 'ab' * 32
DBIK_TYPE_B64     = Base64.strict_encode64('dbik-type'.ljust(32, "\x00"))
DBIK_SERIAL_B64   = Base64.strict_encode64("\x01".ljust(32, "\x00"))
DBIK_SUBJECT_HEX  = "02#{'ab' * 32}".freeze
DBIK_CERTIFIER_HEX = "03#{'cd' * 32}".freeze
DBIK_IDENTITY_HEX  = "02#{'ee' * 32}".freeze

RSpec.describe 'BSV::Wallet::Serializer::DiscoverByIdentityKey' do
  subject(:mod) { BSV::Wallet::Serializer::DiscoverByIdentityKey }

  let(:identity_cert) do
    {
      type: DBIK_TYPE_B64,
      serial_number: DBIK_SERIAL_B64,
      subject: DBIK_SUBJECT_HEX,
      certifier: DBIK_CERTIFIER_HEX,
      revocation_outpoint: "#{DBIK_TXID}.0",
      fields: { 'field1' => 'value1' },
      signature: nil,
      certifier_info: { name: 'Test CA', icon_url: 'https://ca.example/icon',
                        description: 'A test CA', trust: 3 },
      publicly_revealed_keyring: {},
      decrypted_fields: {}
    }
  end

  describe '.serialize_args / .deserialize_args' do
    it 'round-trips identity_key with nil limit/offset/seek_permission' do
      args = { identity_key: DBIK_IDENTITY_HEX, limit: nil, offset: nil,
               seek_permission: nil }
      decoded = mod.deserialize_args(mod.serialize_args(args))
      expect(decoded[:identity_key]).to eq(DBIK_IDENTITY_HEX)
      expect(decoded[:limit]).to be_nil
      expect(decoded[:offset]).to be_nil
      expect(decoded[:seek_permission]).to be_nil
    end

    it 'round-trips with limit and offset set' do
      args = { identity_key: DBIK_IDENTITY_HEX, limit: 10, offset: 5,
               seek_permission: nil }
      decoded = mod.deserialize_args(mod.serialize_args(args))
      expect(decoded[:limit]).to eq(10)
      expect(decoded[:offset]).to eq(5)
    end

    it 'round-trips seek_permission true' do
      args = { identity_key: DBIK_IDENTITY_HEX, limit: nil, offset: nil,
               seek_permission: true }
      decoded = mod.deserialize_args(mod.serialize_args(args))
      expect(decoded[:seek_permission]).to be(true)
    end

    it 'round-trips seek_permission false' do
      args = { identity_key: DBIK_IDENTITY_HEX, limit: nil, offset: nil,
               seek_permission: false }
      decoded = mod.deserialize_args(mod.serialize_args(args))
      expect(decoded[:seek_permission]).to be(false)
    end
  end

  describe '.serialize_result / .deserialize_result' do
    it 'round-trips with one identity certificate' do
      result = { total_certificates: 1, certificates: [identity_cert] }
      decoded = mod.deserialize_result(mod.serialize_result(result))
      expect(decoded[:total_certificates]).to eq(1)
      expect(decoded[:certificates][0][:certifier_info][:name]).to eq('Test CA')
    end

    it 'round-trips with zero certificates' do
      result = { total_certificates: 0, certificates: [] }
      decoded = mod.deserialize_result(mod.serialize_result(result))
      expect(decoded[:total_certificates]).to eq(0)
      expect(decoded[:certificates]).to eq([])
    end
  end
end
