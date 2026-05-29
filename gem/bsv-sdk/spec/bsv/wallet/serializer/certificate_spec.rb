# frozen_string_literal: true

require 'spec_helper'
require 'base64'

CERT_TXID = 'ab' * 32
CERT_TYPE_B64 = Base64.strict_encode64('test-cert-type'.ljust(32, "\x00"))
CERT_SERIAL_B64 = Base64.strict_encode64("\x01\x02\x03".ljust(32, "\x00"))
CERT_SUBJECT_HEX = "02#{'ab' * 32}".freeze
CERT_CERTIFIER_HEX = "03#{'cd' * 32}".freeze

RSpec.describe 'BSV::Wallet::Serializer::Certificate' do
  subject(:mod) { BSV::Wallet::Serializer::Certificate }

  let(:base_cert) do
    {
      type: CERT_TYPE_B64,
      serial_number: CERT_SERIAL_B64,
      subject: CERT_SUBJECT_HEX,
      certifier: CERT_CERTIFIER_HEX,
      revocation_outpoint: "#{CERT_TXID}.0",
      fields: { 'field2' => 'value2', 'field1' => 'value1' },
      signature: nil
    }
  end

  describe '.serialize_certificate / .deserialize_certificate' do
    it 'round-trips a full certificate without signature' do
      bytes = mod.serialize_certificate(base_cert, include_signature: false)
      decoded = mod.deserialize_certificate(bytes)
      expect(decoded[:type]).to eq(CERT_TYPE_B64)
      expect(decoded[:serial_number]).to eq(CERT_SERIAL_B64)
      expect(decoded[:subject]).to eq(CERT_SUBJECT_HEX)
      expect(decoded[:certifier]).to eq(CERT_CERTIFIER_HEX)
      expect(decoded[:revocation_outpoint]).to eq("#{CERT_TXID}.0")
      expect(decoded[:fields]).to eq({ 'field1' => 'value1', 'field2' => 'value2' })
      expect(decoded[:signature]).to be_nil
    end

    it 'round-trips a certificate with a signature' do
      sig_hex = 'deadbeef' * 18
      cert_with_sig = base_cert.merge(signature: sig_hex)
      bytes = mod.serialize_certificate(cert_with_sig, include_signature: true)
      decoded = mod.deserialize_certificate(bytes)
      expect(decoded[:signature]).to eq(sig_hex)
    end

    it 'writes fields in sorted order' do
      bytes = mod.serialize_certificate(base_cert, include_signature: false)
      r = BSV::Wallet::Wire::Reader.new(bytes)
      r.read_bytes(32)  # type
      r.read_bytes(32)  # serial
      r.read_bytes(33)  # subject
      r.read_bytes(33)  # certifier
      r.read_bytes(32)  # txid display order
      r.read_varint     # vout (varint)
      count = r.read_varint
      expect(count).to eq(2)
      first_name = r.read_str_with_varint_len
      expect(first_name).to eq('field1')
    end

    it 'round-trips a certificate with zero fields' do
      cert_empty = base_cert.merge(fields: {})
      decoded = mod.deserialize_certificate(mod.serialize_certificate(cert_empty))
      expect(decoded[:fields]).to eq({})
    end

    it 'round-trips revocation_outpoint nil as null outpoint' do
      cert_nil_outpoint = base_cert.merge(revocation_outpoint: nil)
      decoded = mod.deserialize_certificate(mod.serialize_certificate(cert_nil_outpoint))
      expect(decoded[:revocation_outpoint]).to eq("#{'00' * 32}.0")
    end
  end

  describe '.serialize_identity_certificate / .deserialize_identity_certificate' do
    let(:identity_cert) do
      base_cert.merge(
        certifier_info: {
          name: 'Acme Corp',
          icon_url: 'https://acme.com/icon.png',
          description: 'Test certifier',
          trust: 5
        },
        publicly_revealed_keyring: {
          'field1' => Base64.strict_encode64('keydata1')
        },
        decrypted_fields: { 'field1' => 'plaintext' }
      )
    end

    it 'round-trips a full identity certificate' do
      bytes = mod.serialize_identity_certificate(identity_cert)
      r = BSV::Wallet::Wire::Reader.new(bytes)
      decoded = mod.deserialize_identity_certificate(r)
      expect(decoded[:certifier_info][:name]).to eq('Acme Corp')
      expect(decoded[:certifier_info][:trust]).to eq(5)
      expect(decoded[:publicly_revealed_keyring]['field1']).to eq(
        Base64.strict_encode64('keydata1')
      )
      expect(decoded[:decrypted_fields]['field1']).to eq('plaintext')
    end

    it 'round-trips empty keyring and decrypted_fields' do
      cert = identity_cert.merge(
        publicly_revealed_keyring: {},
        decrypted_fields: {}
      )
      bytes = mod.serialize_identity_certificate(cert)
      r = BSV::Wallet::Wire::Reader.new(bytes)
      decoded = mod.deserialize_identity_certificate(r)
      expect(decoded[:publicly_revealed_keyring]).to eq({})
      expect(decoded[:decrypted_fields]).to eq({})
    end

    it 'writes keyring entries sorted by key' do
      cert = identity_cert.merge(
        publicly_revealed_keyring: {
          'zzz' => Base64.strict_encode64('z'),
          'aaa' => Base64.strict_encode64('a')
        }
      )
      bytes = mod.serialize_identity_certificate(cert)
      r = BSV::Wallet::Wire::Reader.new(bytes)
      decoded = mod.deserialize_identity_certificate(r)
      expect(decoded[:publicly_revealed_keyring].keys).to contain_exactly('aaa', 'zzz')
    end
  end
end
