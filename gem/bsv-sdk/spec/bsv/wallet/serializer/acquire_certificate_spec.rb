# frozen_string_literal: true

require 'spec_helper'
require 'base64'

ACQ_TXID = 'e2b4418574d1b0b073b74a0d3c0a3afd39e20d5f68b66dff8371e1210c8155a7'
ACQ_TYPE_B64 = Base64.strict_encode64('acq-cert-type'.ljust(32, "\x00"))
ACQ_SERIAL_B64 = Base64.strict_encode64("\x01".ljust(32, "\x00"))
ACQ_CERTIFIER_HEX = "02#{'01' * 32}".freeze
ACQ_KEYRING_B64 = Base64.strict_encode64('keyring_data')

RSpec.describe 'BSV::Wallet::Serializer::AcquireCertificate' do
  subject(:mod) { BSV::Wallet::Serializer::AcquireCertificate }

  describe '.serialize_args / .deserialize_args — direct protocol' do
    let(:args_direct) do
      {
        type: ACQ_TYPE_B64,
        certifier: ACQ_CERTIFIER_HEX,
        acquisition_protocol: :direct,
        fields: { 'field2' => 'value2', 'field1' => 'value1' },
        serial_number: ACQ_SERIAL_B64,
        revocation_outpoint: "#{ACQ_TXID}.0",
        signature: nil,
        keyring_revealer: { certifier: true },
        keyring_for_subject: { 'field1' => ACQ_KEYRING_B64 },
        privileged: nil,
        privileged_reason: nil
      }
    end

    it 'round-trips direct acquisition with certifier revealer' do
      decoded = mod.deserialize_args(mod.serialize_args(args_direct))
      expect(decoded[:acquisition_protocol]).to eq(:direct)
      expect(decoded[:type]).to eq(ACQ_TYPE_B64)
      expect(decoded[:certifier]).to eq(ACQ_CERTIFIER_HEX)
      expect(decoded[:serial_number]).to eq(ACQ_SERIAL_B64)
      expect(decoded[:revocation_outpoint]).to eq("#{ACQ_TXID}.0")
      expect(decoded[:keyring_revealer]).to eq({ certifier: true })
      expect(decoded[:keyring_for_subject]).to eq({ 'field1' => ACQ_KEYRING_B64 })
    end

    it 'round-trips with a pubkey keyring_revealer' do
      revealer_hex = "02#{'ff' * 32}"
      args = args_direct.merge(keyring_revealer: { pub_key: revealer_hex })
      decoded = mod.deserialize_args(mod.serialize_args(args))
      expect(decoded[:keyring_revealer][:pub_key]).to eq(revealer_hex)
    end

    it 'round-trips with empty keyring_for_subject' do
      args = args_direct.merge(keyring_for_subject: {})
      decoded = mod.deserialize_args(mod.serialize_args(args))
      expect(decoded[:keyring_for_subject]).to eq({})
    end

    it 'round-trips with privileged true and reason' do
      args = args_direct.merge(privileged: true, privileged_reason: 'test-reason')
      decoded = mod.deserialize_args(mod.serialize_args(args))
      expect(decoded[:privileged]).to be(true)
      expect(decoded[:privileged_reason]).to eq('test-reason')
    end

    it 'round-trips with privileged false' do
      args = args_direct.merge(privileged: false, privileged_reason: nil)
      decoded = mod.deserialize_args(mod.serialize_args(args))
      expect(decoded[:privileged]).to be(false)
    end
  end

  describe '.serialize_args / .deserialize_args — issuance protocol' do
    let(:args_issuance) do
      {
        type: ACQ_TYPE_B64,
        certifier: ACQ_CERTIFIER_HEX,
        acquisition_protocol: :issuance,
        fields: { 'field1' => 'value1' },
        certifier_url: 'https://certifier.example.com',
        privileged: nil,
        privileged_reason: nil
      }
    end

    it 'round-trips issuance acquisition' do
      decoded = mod.deserialize_args(mod.serialize_args(args_issuance))
      expect(decoded[:acquisition_protocol]).to eq(:issuance)
      expect(decoded[:certifier_url]).to eq('https://certifier.example.com')
    end
  end

  describe '.serialize_result / .deserialize_result' do
    it 'round-trips a certificate result' do
      cert = {
        type: ACQ_TYPE_B64,
        serial_number: ACQ_SERIAL_B64,
        subject: "02#{'ab' * 32}",
        certifier: ACQ_CERTIFIER_HEX,
        revocation_outpoint: "#{ACQ_TXID}.0",
        fields: {},
        signature: nil
      }
      decoded = mod.deserialize_result(mod.serialize_result(certificate: cert))
      expect(decoded[:certificate][:type]).to eq(ACQ_TYPE_B64)
    end
  end
end
