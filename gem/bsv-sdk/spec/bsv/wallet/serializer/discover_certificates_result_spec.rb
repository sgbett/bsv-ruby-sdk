# frozen_string_literal: true

require 'spec_helper'
require 'base64'

DISC_TXID = 'ab' * 32
DISC_TYPE_B64 = Base64.strict_encode64('disc-type'.ljust(32, "\x00"))
DISC_SERIAL_B64 = Base64.strict_encode64("\x01".ljust(32, "\x00"))
DISC_SUBJECT_HEX = "02#{'ab' * 32}".freeze
DISC_CERTIFIER_HEX = "03#{'cd' * 32}".freeze

RSpec.describe 'BSV::Wallet::Serializer::DiscoverCertificatesResult' do
  subject(:mod) { BSV::Wallet::Serializer::DiscoverCertificatesResult }

  let(:identity_cert) do
    {
      type: DISC_TYPE_B64,
      serial_number: DISC_SERIAL_B64,
      subject: DISC_SUBJECT_HEX,
      certifier: DISC_CERTIFIER_HEX,
      revocation_outpoint: "#{DISC_TXID}.0",
      fields: { 'field1' => 'value1' },
      signature: nil,
      certifier_info: {
        name: 'Test CA',
        icon_url: 'https://ca.example/icon',
        description: 'A test CA',
        trust: 3
      },
      publicly_revealed_keyring: {},
      decrypted_fields: {}
    }
  end

  it 'round-trips with one certificate' do
    result = { total_certificates: 1, certificates: [identity_cert] }
    decoded = mod.deserialize(mod.serialize(result))
    expect(decoded[:total_certificates]).to eq(1)
    expect(decoded[:certificates][0][:certifier_info][:name]).to eq('Test CA')
    expect(decoded[:certificates][0][:type]).to eq(DISC_TYPE_B64)
  end

  it 'round-trips with zero certificates' do
    result = { total_certificates: 0, certificates: [] }
    decoded = mod.deserialize(mod.serialize(result))
    expect(decoded[:total_certificates]).to eq(0)
    expect(decoded[:certificates]).to eq([])
  end

  it 'round-trips with multiple certificates' do
    cert2 = identity_cert.merge(
      type: Base64.strict_encode64('type2'.ljust(32, "\x00")),
      certifier_info: identity_cert[:certifier_info].merge(name: 'Second CA')
    )
    result = { total_certificates: 2, certificates: [identity_cert, cert2] }
    decoded = mod.deserialize(mod.serialize(result))
    expect(decoded[:total_certificates]).to eq(2)
    expect(decoded[:certificates].map { |c| c[:certifier_info][:name] }).to eq(['Test CA', 'Second CA'])
  end
end
