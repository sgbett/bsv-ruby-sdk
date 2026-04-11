# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'BSV::Identity types' do
  describe BSV::Identity::DisplayableIdentity do
    subject(:identity) do
      described_class.new(
        name: 'Alice',
        avatar_url: 'https://example.com/avatar.png',
        abbreviated_key: 'abc...xyz',
        identity_key: 'abcdef1234567890'
      )
    end

    it 'exposes name' do
      expect(identity.name).to eq('Alice')
    end

    it 'exposes avatar_url' do
      expect(identity.avatar_url).to eq('https://example.com/avatar.png')
    end

    it 'exposes abbreviated_key' do
      expect(identity.abbreviated_key).to eq('abc...xyz')
    end

    it 'exposes identity_key' do
      expect(identity.identity_key).to eq('abcdef1234567890')
    end

    it 'defaults badge_icon_url to nil' do
      expect(identity.badge_icon_url).to be_nil
    end

    it 'defaults badge_label to nil' do
      expect(identity.badge_label).to be_nil
    end

    it 'defaults badge_click_url to nil' do
      expect(identity.badge_click_url).to be_nil
    end

    it 'accepts optional badge fields' do
      instance = described_class.new(
        name: 'Bob',
        avatar_url: 'https://example.com/bob.png',
        abbreviated_key: 'bbb...bbb',
        identity_key: 'bbbbb',
        badge_icon_url: 'https://example.com/badge.png',
        badge_label: 'Verified',
        badge_click_url: 'https://example.com/verify'
      )
      expect(instance.badge_icon_url).to eq('https://example.com/badge.png')
      expect(instance.badge_label).to eq('Verified')
      expect(instance.badge_click_url).to eq('https://example.com/verify')
    end
  end

  describe BSV::Identity::CertifierInfo do
    it 'exposes name' do
      instance = described_class.new(name: 'Trust Authority')
      expect(instance.name).to eq('Trust Authority')
    end

    it 'defaults icon_url to nil' do
      instance = described_class.new(name: 'Trust Authority')
      expect(instance.icon_url).to be_nil
    end

    it 'accepts icon_url when provided' do
      instance = described_class.new(name: 'Trust Authority', icon_url: 'https://example.com/icon.png')
      expect(instance.icon_url).to eq('https://example.com/icon.png')
    end
  end

  describe BSV::Identity::IdentityCertificate do
    subject(:cert) { described_class.new(certificate: cert_data, decrypted_fields: field_data) }

    let(:cert_data)   { { type: 'xCert', subject: 'abc123', fields: {} } }
    let(:field_data)  { { 'handle' => '@alice' } }

    it 'exposes certificate' do
      expect(cert.certificate).to eq(cert_data)
    end

    it 'exposes decrypted_fields' do
      expect(cert.decrypted_fields).to eq(field_data)
    end

    it 'defaults certifier_info to nil' do
      expect(cert.certifier_info).to be_nil
    end

    it 'accepts certifier_info when provided' do
      info     = BSV::Identity::CertifierInfo.new(name: 'Trust Authority')
      instance = described_class.new(
        certificate: cert_data,
        decrypted_fields: field_data,
        certifier_info: info
      )
      expect(instance.certifier_info).to be_a(BSV::Identity::CertifierInfo)
      expect(instance.certifier_info.name).to eq('Trust Authority')
    end
  end

  describe BSV::Identity::ClientOptions do
    subject(:opts) do
      described_class.new(
        protocol_id: [1, 'identity'],
        key_id: '1',
        token_amount: 1,
        output_index: 0
      )
    end

    it 'exposes protocol_id' do
      expect(opts.protocol_id).to eq([1, 'identity'])
    end

    it 'exposes key_id' do
      expect(opts.key_id).to eq('1')
    end

    it 'exposes token_amount' do
      expect(opts.token_amount).to eq(1)
    end

    it 'exposes output_index' do
      expect(opts.output_index).to eq(0)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
