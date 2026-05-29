# frozen_string_literal: true

require 'spec_helper'
require 'base64'

PC_TXID = 'ab' * 32
PC_TYPE_B64 = Base64.strict_encode64('pc-cert-type'.ljust(32, "\x00"))
PC_SERIAL_B64 = Base64.strict_encode64("\x01".ljust(32, "\x00"))
PC_SUBJECT_HEX = "02#{'ab' * 32}".freeze
PC_CERTIFIER_HEX = "03#{'cd' * 32}".freeze
PC_VERIFIER_HEX = "02#{'ef' * 32}".freeze

RSpec.describe 'BSV::Wallet::Serializer::ProveCertificate' do
  subject(:mod) { BSV::Wallet::Serializer::ProveCertificate }

  let(:cert) do
    {
      type: PC_TYPE_B64, serial_number: PC_SERIAL_B64,
      subject: PC_SUBJECT_HEX, certifier: PC_CERTIFIER_HEX,
      revocation_outpoint: "#{PC_TXID}.0",
      fields: { 'field1' => 'val1', 'field2' => 'val2' },
      signature: nil
    }
  end

  describe '.serialize_args / .deserialize_args' do
    it 'round-trips with multiple fields_to_reveal' do
      args = { certificate: cert, fields_to_reveal: %w[field1 field2],
               verifier: PC_VERIFIER_HEX, privileged: nil, privileged_reason: nil }
      decoded = mod.deserialize_args(mod.serialize_args(args))
      expect(decoded[:fields_to_reveal]).to eq(%w[field1 field2])
      expect(decoded[:verifier]).to eq(PC_VERIFIER_HEX)
      expect(decoded[:certificate][:type]).to eq(PC_TYPE_B64)
    end

    it 'round-trips with empty fields_to_reveal' do
      args = { certificate: cert, fields_to_reveal: [],
               verifier: PC_VERIFIER_HEX, privileged: nil, privileged_reason: nil }
      decoded = mod.deserialize_args(mod.serialize_args(args))
      expect(decoded[:fields_to_reveal]).to eq([])
    end

    it 'round-trips privileged params' do
      args = { certificate: cert, fields_to_reveal: [],
               verifier: PC_VERIFIER_HEX, privileged: true, privileged_reason: 'priv-reason' }
      decoded = mod.deserialize_args(mod.serialize_args(args))
      expect(decoded[:privileged]).to be(true)
      expect(decoded[:privileged_reason]).to eq('priv-reason')
    end

    it 'preserves certificate fields sorted in round-trip' do
      args = { certificate: cert, fields_to_reveal: ['field1'],
               verifier: PC_VERIFIER_HEX, privileged: nil, privileged_reason: nil }
      decoded = mod.deserialize_args(mod.serialize_args(args))
      expect(decoded[:certificate][:fields].keys.sort).to eq(%w[field1 field2])
    end
  end

  describe '.serialize_result / .deserialize_result' do
    it 'round-trips keyring_for_verifier with one entry' do
      keyring = { 'field1' => Base64.strict_encode64('keydata') }
      result = { keyring_for_verifier: keyring }
      decoded = mod.deserialize_result(mod.serialize_result(result))
      expect(decoded[:keyring_for_verifier]).to eq(keyring)
    end

    it 'round-trips empty keyring_for_verifier' do
      result = { keyring_for_verifier: {} }
      decoded = mod.deserialize_result(mod.serialize_result(result))
      expect(decoded[:keyring_for_verifier]).to eq({})
    end

    it 'round-trips multi-field keyring' do
      keyring = {
        'field2' => Base64.strict_encode64('data2'),
        'field1' => Base64.strict_encode64('data1')
      }
      result = { keyring_for_verifier: keyring }
      decoded = mod.deserialize_result(mod.serialize_result(result))
      expect(decoded[:keyring_for_verifier]).to eq(keyring)
    end
  end
end
