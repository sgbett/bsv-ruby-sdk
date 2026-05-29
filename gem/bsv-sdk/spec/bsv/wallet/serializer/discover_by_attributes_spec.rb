# frozen_string_literal: true

require 'spec_helper'
require 'base64'

DBA_TXID          = 'ab' * 32
DBA_TYPE_B64      = Base64.strict_encode64('dba-type'.ljust(32, "\x00"))
DBA_SERIAL_B64    = Base64.strict_encode64("\x01".ljust(32, "\x00"))
DBA_SUBJECT_HEX   = "02#{'ab' * 32}".freeze
DBA_CERTIFIER_HEX = "03#{'cd' * 32}".freeze

RSpec.describe 'BSV::Wallet::Serializer::DiscoverByAttributes' do
  subject(:mod) { BSV::Wallet::Serializer::DiscoverByAttributes }

  let(:identity_cert) do
    {
      type: DBA_TYPE_B64,
      serial_number: DBA_SERIAL_B64,
      subject: DBA_SUBJECT_HEX,
      certifier: DBA_CERTIFIER_HEX,
      revocation_outpoint: "#{DBA_TXID}.0",
      fields: { 'field1' => 'value1' },
      signature: nil,
      certifier_info: { name: 'Test CA', icon_url: 'https://ca.example/icon',
                        description: 'A test CA', trust: 3 },
      publicly_revealed_keyring: {},
      decrypted_fields: {}
    }
  end

  describe '.serialize_args / .deserialize_args' do
    it 'round-trips with multiple attributes' do
      args = { attributes: { 'email' => 'user@example.com', 'name' => 'Alice' },
               limit: nil, offset: nil, seek_permission: nil }
      decoded = mod.deserialize_args(mod.serialize_args(args))
      expect(decoded[:attributes]).to eq({ 'email' => 'user@example.com', 'name' => 'Alice' })
    end

    it 'round-trips with empty attributes map' do
      args = { attributes: {}, limit: nil, offset: nil, seek_permission: nil }
      decoded = mod.deserialize_args(mod.serialize_args(args))
      expect(decoded[:attributes]).to eq({})
    end

    it 'round-trips with nil attributes (treated as empty)' do
      args = { attributes: nil, limit: nil, offset: nil, seek_permission: nil }
      decoded = mod.deserialize_args(mod.serialize_args(args))
      expect(decoded[:attributes]).to eq({})
    end

    it 'writes attributes in sorted key order' do
      args = { attributes: { 'zzz' => 'last', 'aaa' => 'first' },
               limit: nil, offset: nil, seek_permission: nil }
      decoded = mod.deserialize_args(mod.serialize_args(args))
      expect(decoded[:attributes].keys).to contain_exactly('aaa', 'zzz')
    end

    it 'round-trips with limit and offset' do
      args = { attributes: { 'name' => 'Bob' }, limit: 20, offset: 10,
               seek_permission: nil }
      decoded = mod.deserialize_args(mod.serialize_args(args))
      expect(decoded[:limit]).to eq(20)
      expect(decoded[:offset]).to eq(10)
    end

    it 'round-trips seek_permission true' do
      args = { attributes: {}, limit: nil, offset: nil, seek_permission: true }
      decoded = mod.deserialize_args(mod.serialize_args(args))
      expect(decoded[:seek_permission]).to be(true)
    end
  end

  describe '.serialize_result / .deserialize_result' do
    it 'round-trips with one identity certificate' do
      result = { total_certificates: 1, certificates: [identity_cert] }
      decoded = mod.deserialize_result(mod.serialize_result(result))
      expect(decoded[:total_certificates]).to eq(1)
      expect(decoded[:certificates][0][:type]).to eq(DBA_TYPE_B64)
    end

    it 'round-trips with zero certificates' do
      result = { total_certificates: 0, certificates: [] }
      decoded = mod.deserialize_result(mod.serialize_result(result))
      expect(decoded[:total_certificates]).to eq(0)
      expect(decoded[:certificates]).to eq([])
    end
  end
end
