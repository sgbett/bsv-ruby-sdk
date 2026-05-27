# frozen_string_literal: true

require 'spec_helper'
require 'base64'

RC_TYPE_B64   = Base64.strict_encode64('rc-cert-type'.ljust(32, "\x00"))
RC_SERIAL_B64 = Base64.strict_encode64("\x01".ljust(32, "\x00"))
RC_CERT_HEX   = "02#{'ab' * 32}".freeze

RSpec.describe 'BSV::Wallet::Serializer::RelinquishCertificate' do
  subject(:mod) { BSV::Wallet::Serializer::RelinquishCertificate }

  describe '.serialize_args / .deserialize_args' do
    let(:args) do
      { type: RC_TYPE_B64, serial_number: RC_SERIAL_B64, certifier: RC_CERT_HEX }
    end

    it 'round-trips type, serial_number and certifier' do
      decoded = mod.deserialize_args(mod.serialize_args(args))
      expect(decoded[:type]).to eq(RC_TYPE_B64)
      expect(decoded[:serial_number]).to eq(RC_SERIAL_B64)
      expect(decoded[:certifier]).to eq(RC_CERT_HEX)
    end

    it 'encodes to exactly 97 bytes (32 + 32 + 33)' do
      expect(mod.serialize_args(args).bytesize).to eq(97)
    end
  end

  describe '.serialize_result / .deserialize_result' do
    it 'serializes to empty bytes' do
      expect(mod.serialize_result(relinquished: true).bytesize).to eq(0)
    end

    it 'deserializes empty bytes as relinquished: true' do
      decoded = mod.deserialize_result(''.b)
      expect(decoded[:relinquished]).to be(true)
    end
  end
end
