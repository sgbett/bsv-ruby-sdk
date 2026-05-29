# frozen_string_literal: true

require 'spec_helper'
require 'base64'

LC_TXID = 'ab' * 32
LC_TYPE_B64 = Base64.strict_encode64('lc-cert-type'.ljust(32, "\x00"))
LC_SERIAL_B64 = Base64.strict_encode64("\x01".ljust(32, "\x00"))
LC_CERTIFIER_HEX = "02#{'01' * 32}".freeze
LC_SUBJECT_HEX = "03#{'ab' * 32}".freeze

RSpec.describe 'BSV::Wallet::Serializer::ListCertificates' do
  subject(:mod) { BSV::Wallet::Serializer::ListCertificates }

  describe '.serialize_args / .deserialize_args' do
    it 'round-trips full args' do
      args = {
        certifiers: [LC_CERTIFIER_HEX],
        types: [LC_TYPE_B64],
        limit: 5,
        offset: 0,
        privileged: nil,
        privileged_reason: nil
      }
      decoded = mod.deserialize_args(mod.serialize_args(args))
      expect(decoded[:certifiers]).to eq([LC_CERTIFIER_HEX])
      expect(decoded[:types]).to eq([LC_TYPE_B64])
      expect(decoded[:limit]).to eq(5)
      expect(decoded[:offset]).to eq(0)
    end

    it 'round-trips empty certifiers and types' do
      args = { certifiers: [], types: [], limit: nil, offset: nil,
               privileged: nil, privileged_reason: nil }
      decoded = mod.deserialize_args(mod.serialize_args(args))
      expect(decoded[:certifiers]).to eq([])
      expect(decoded[:types]).to eq([])
    end

    it 'round-trips privileged flag' do
      args = { certifiers: [], types: [], limit: nil, offset: nil,
               privileged: true, privileged_reason: 'reason' }
      decoded = mod.deserialize_args(mod.serialize_args(args))
      expect(decoded[:privileged]).to be(true)
      expect(decoded[:privileged_reason]).to eq('reason')
    end

    it 'round-trips multiple certifiers and types' do
      cert2 = "03#{'ff' * 32}"
      type2 = Base64.strict_encode64('type2'.ljust(32, "\x00"))
      args = { certifiers: [LC_CERTIFIER_HEX, cert2], types: [LC_TYPE_B64, type2],
               limit: 10, offset: 5, privileged: nil, privileged_reason: nil }
      decoded = mod.deserialize_args(mod.serialize_args(args))
      expect(decoded[:certifiers]).to contain_exactly(LC_CERTIFIER_HEX, cert2)
      expect(decoded[:types]).to contain_exactly(LC_TYPE_B64, type2)
    end
  end

  describe '.serialize_result / .deserialize_result' do
    let(:base_cert) do
      {
        type: LC_TYPE_B64, serial_number: LC_SERIAL_B64,
        subject: LC_SUBJECT_HEX, certifier: LC_CERTIFIER_HEX,
        revocation_outpoint: "#{LC_TXID}.0", fields: {}, signature: nil
      }
    end

    it 'round-trips with one certificate no keyring' do
      result = {
        total_certificates: 1,
        certificates: [{ certificate: base_cert, keyring: nil, verifier: nil }]
      }
      decoded = mod.deserialize_result(mod.serialize_result(result))
      expect(decoded[:total_certificates]).to eq(1)
      expect(decoded[:certificates][0][:certificate][:type]).to eq(LC_TYPE_B64)
      expect(decoded[:certificates][0][:keyring]).to be_nil
    end

    it 'round-trips with a keyring' do
      keyring = { 'field1' => Base64.strict_encode64('keydata') }
      result = {
        total_certificates: 1,
        certificates: [{ certificate: base_cert, keyring: keyring, verifier: nil }]
      }
      decoded = mod.deserialize_result(mod.serialize_result(result))
      expect(decoded[:certificates][0][:keyring]).to eq(keyring)
    end

    it 'round-trips with zero certificates' do
      result = { total_certificates: 0, certificates: [] }
      decoded = mod.deserialize_result(mod.serialize_result(result))
      expect(decoded[:total_certificates]).to eq(0)
      expect(decoded[:certificates]).to eq([])
    end
  end
end
