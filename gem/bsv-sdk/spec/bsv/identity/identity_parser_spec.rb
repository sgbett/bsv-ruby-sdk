# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'BSV::Identity::IdentityParser' do
  subject(:parser) { BSV::Identity::IdentityParser }

  let(:default_identity) { BSV::Identity::Constants::DEFAULT_IDENTITY }
  let(:types)            { BSV::Identity::Constants::KNOWN_IDENTITY_TYPES }
  let(:certifier) do
    BSV::Identity::CertifierInfo.new(name: 'TrustCo', icon_url: 'https://example.com/icon.png')
  end

  # Builds an IdentityCertificate for a well-known type key.
  def cert_for(type_key, fields, certifier_info: nil)
    BSV::Identity::IdentityCertificate.new(
      certificate: { type: BSV::Identity::Constants::KNOWN_IDENTITY_TYPES[type_key],
                     subject: 'abcdefghij1234567890' },
      decrypted_fields: fields,
      certifier_info: certifier_info
    )
  end

  # Builds an IdentityCertificate for an arbitrary type Base64 string.
  def cert_with_type(type_b64, fields, certifier_info: nil, subject: 'abcdefghij1234567890')
    BSV::Identity::IdentityCertificate.new(
      certificate: { type: type_b64, subject: subject },
      decrypted_fields: fields,
      certifier_info: certifier_info
    )
  end

  # ---------------------------------------------------------------------------
  # Known identity types
  # ---------------------------------------------------------------------------

  describe 'xCert' do
    subject(:result) do
      parser.parse(cert_for(:x_cert, { 'userName' => '@alice', 'profilePhoto' => 'xphoto' },
                            certifier_info: certifier))
    end

    it 'extracts name from userName' do
      expect(result.name).to eq('@alice')
    end

    it 'extracts avatar from profilePhoto' do
      expect(result.avatar_url).to eq('xphoto')
    end

    it 'includes certifier name in badge label' do
      expect(result.badge_label).to eq('X account certified by TrustCo')
    end

    it 'uses certifier icon_url as badge icon' do
      expect(result.badge_icon_url).to eq('https://example.com/icon.png')
    end

    it 'sets badge click URL to socialcert.net' do
      expect(result.badge_click_url).to eq('https://socialcert.net')
    end
  end

  describe 'discordCert' do
    subject(:result) do
      parser.parse(cert_for(:discord_cert, { 'userName' => 'bob#1234', 'profilePhoto' => 'dphoto' },
                            certifier_info: certifier))
    end

    it 'extracts name from userName' do
      expect(result.name).to eq('bob#1234')
    end

    it 'extracts avatar from profilePhoto' do
      expect(result.avatar_url).to eq('dphoto')
    end

    it 'includes certifier name in badge label' do
      expect(result.badge_label).to eq('Discord account certified by TrustCo')
    end

    it 'sets badge click URL to socialcert.net' do
      expect(result.badge_click_url).to eq('https://socialcert.net')
    end
  end

  describe 'emailCert' do
    subject(:result) do
      parser.parse(cert_for(:email_cert, { 'email' => 'alice@example.com' }, certifier_info: certifier))
    end

    it 'extracts name from email field' do
      expect(result.name).to eq('alice@example.com')
    end

    it 'uses the fixed email avatar opaque string' do
      expect(result.avatar_url).to eq(BSV::Identity::IdentityParser::EMAIL_AVATAR)
    end

    it 'includes certifier name in badge label' do
      expect(result.badge_label).to eq('Email certified by TrustCo')
    end

    it 'sets badge click URL to socialcert.net' do
      expect(result.badge_click_url).to eq('https://socialcert.net')
    end
  end

  describe 'phoneCert' do
    subject(:result) do
      parser.parse(cert_for(:phone_cert, { 'phoneNumber' => '+447700900123' }, certifier_info: certifier))
    end

    it 'extracts name from phoneNumber field' do
      expect(result.name).to eq('+447700900123')
    end

    it 'uses the fixed phone avatar opaque string' do
      expect(result.avatar_url).to eq(BSV::Identity::IdentityParser::PHONE_AVATAR)
    end

    it 'includes certifier name in badge label' do
      expect(result.badge_label).to eq('Phone certified by TrustCo')
    end

    it 'sets badge click URL to socialcert.net' do
      expect(result.badge_click_url).to eq('https://socialcert.net')
    end
  end

  describe 'identiCert' do
    subject(:result) do
      parser.parse(cert_for(:identi_cert,
                            { 'firstName' => 'Jane', 'lastName' => 'Smith', 'profilePhoto' => 'iphoto' },
                            certifier_info: certifier))
    end

    it 'combines firstName and lastName for name' do
      expect(result.name).to eq('Jane Smith')
    end

    it 'extracts avatar from profilePhoto' do
      expect(result.avatar_url).to eq('iphoto')
    end

    it 'includes certifier name in badge label' do
      expect(result.badge_label).to eq('Government ID certified by TrustCo')
    end

    it 'sets badge click URL to identicert.me' do
      expect(result.badge_click_url).to eq('https://identicert.me')
    end
  end

  describe 'registrant' do
    subject(:result) do
      parser.parse(cert_for(:registrant, { 'name' => 'Acme Corp', 'icon' => 'acme_icon' },
                            certifier_info: certifier))
    end

    it 'extracts name from name field' do
      expect(result.name).to eq('Acme Corp')
    end

    it 'extracts avatar from icon field' do
      expect(result.avatar_url).to eq('acme_icon')
    end

    it 'includes certifier name in badge label' do
      expect(result.badge_label).to eq('Entity certified by TrustCo')
    end

    it 'sets badge click URL to projectbabbage.com/docs/registrant' do
      expect(result.badge_click_url).to eq('https://projectbabbage.com/docs/registrant')
    end
  end

  describe 'coolCert' do
    it 'returns Cool Person! when cool field is the string true' do
      result = parser.parse(cert_for(:cool_cert, { 'cool' => 'true' }))
      expect(result.name).to eq('Cool Person!')
    end

    it 'returns Not cool! when cool field is anything other than true' do
      result = parser.parse(cert_for(:cool_cert, { 'cool' => 'false' }))
      expect(result.name).to eq('Not cool!')
    end

    it 'returns Not cool! when cool field is absent' do
      result = parser.parse(cert_for(:cool_cert, {}))
      expect(result.name).to eq('Not cool!')
    end

    it 'sets no badge label' do
      result = parser.parse(cert_for(:cool_cert, { 'cool' => 'true' }))
      expect(result.badge_label).to be_nil
    end
  end

  describe 'anyone' do
    subject(:result) { parser.parse(cert_for(:anyone, {})) }

    it 'returns the name Anyone' do
      expect(result.name).to eq('Anyone')
    end

    it 'uses the anyone avatar opaque string' do
      expect(result.avatar_url).to eq(BSV::Identity::IdentityParser::ANYONE_AVATAR)
    end

    it 'sets the badge label' do
      expect(result.badge_label).to eq('Represents the ability for anyone to access this information.')
    end

    it 'uses the shared badge icon' do
      expect(result.badge_icon_url).to eq(BSV::Identity::IdentityParser::BADGE_ICON)
    end

    it 'sets badge click URL' do
      expect(result.badge_click_url).to eq('https://projectbabbage.com/docs/anyone-identity')
    end
  end

  describe 'self' do
    subject(:result) { parser.parse(cert_for(:self, {})) }

    it 'returns the name You' do
      expect(result.name).to eq('You')
    end

    it 'uses the self avatar opaque string' do
      expect(result.avatar_url).to eq(BSV::Identity::IdentityParser::SELF_AVATAR)
    end

    it 'sets the badge label' do
      expect(result.badge_label).to eq('Represents your ability to access this information.')
    end

    it 'uses the shared badge icon' do
      expect(result.badge_icon_url).to eq(BSV::Identity::IdentityParser::BADGE_ICON)
    end

    it 'sets badge click URL' do
      expect(result.badge_click_url).to eq('https://projectbabbage.com/docs/self-identity')
    end
  end

  # ---------------------------------------------------------------------------
  # Unknown type — generic fallback: name resolution chain
  # ---------------------------------------------------------------------------

  describe 'generic fallback — name resolution' do
    let(:unknown_type) { 'dW5rbm93blR5cGU=' }

    it 'uses name field when present' do
      result = parser.parse(cert_with_type(unknown_type, { 'name' => 'Direct Name' }))
      expect(result.name).to eq('Direct Name')
    end

    it 'falls back to userName when name is absent' do
      result = parser.parse(cert_with_type(unknown_type, { 'userName' => 'username_fallback' }))
      expect(result.name).to eq('username_fallback')
    end

    it 'falls back to firstName + lastName when userName is absent' do
      result = parser.parse(cert_with_type(unknown_type, { 'firstName' => 'John', 'lastName' => 'Doe' }))
      expect(result.name).to eq('John Doe')
    end

    it 'uses only firstName when lastName is absent' do
      result = parser.parse(cert_with_type(unknown_type, { 'firstName' => 'JustFirst' }))
      expect(result.name).to eq('JustFirst')
    end

    it 'uses only lastName when firstName is absent' do
      result = parser.parse(cert_with_type(unknown_type, { 'lastName' => 'JustLast' }))
      expect(result.name).to eq('JustLast')
    end

    it 'falls back to email when no name fields are present' do
      result = parser.parse(cert_with_type(unknown_type, { 'email' => 'test@example.com' }))
      expect(result.name).to eq('test@example.com')
    end

    it 'falls back to default identity name when no recognisable fields are present' do
      result = parser.parse(cert_with_type(unknown_type, {}))
      expect(result.name).to eq(default_identity.name)
    end

    it 'prefers name over userName' do
      result = parser.parse(cert_with_type(unknown_type, { 'name' => 'Full Name', 'userName' => 'handle' }))
      expect(result.name).to eq('Full Name')
    end

    it 'prefers userName over firstName+lastName' do
      result = parser.parse(cert_with_type(unknown_type,
                                           { 'userName' => 'handle', 'firstName' => 'John', 'lastName' => 'Doe' }))
      expect(result.name).to eq('handle')
    end
  end

  # ---------------------------------------------------------------------------
  # Unknown type — generic fallback: avatar resolution chain
  # ---------------------------------------------------------------------------

  describe 'generic fallback — avatar resolution' do
    let(:unknown_type) { 'dW5rbm93blR5cGU=' }

    it 'uses profilePhoto as avatar when present' do
      result = parser.parse(cert_with_type(unknown_type, { 'profilePhoto' => 'pp_url' }))
      expect(result.avatar_url).to eq('pp_url')
    end

    it 'falls back to avatar field' do
      result = parser.parse(cert_with_type(unknown_type, { 'avatar' => 'av_url' }))
      expect(result.avatar_url).to eq('av_url')
    end

    it 'falls back to icon field' do
      result = parser.parse(cert_with_type(unknown_type, { 'icon' => 'ic_url' }))
      expect(result.avatar_url).to eq('ic_url')
    end

    it 'falls back to photo field' do
      result = parser.parse(cert_with_type(unknown_type, { 'photo' => 'ph_url' }))
      expect(result.avatar_url).to eq('ph_url')
    end

    it 'uses default avatar when no photo fields are present' do
      result = parser.parse(cert_with_type(unknown_type, {}))
      expect(result.avatar_url).to eq(default_identity.avatar_url)
    end

    it 'prefers profilePhoto over avatar' do
      result = parser.parse(cert_with_type(unknown_type, { 'profilePhoto' => 'pp', 'avatar' => 'av' }))
      expect(result.avatar_url).to eq('pp')
    end

    it 'prefers avatar over icon' do
      result = parser.parse(cert_with_type(unknown_type, { 'avatar' => 'av', 'icon' => 'ic' }))
      expect(result.avatar_url).to eq('av')
    end

    it 'prefers icon over photo' do
      result = parser.parse(cert_with_type(unknown_type, { 'icon' => 'ic', 'photo' => 'ph' }))
      expect(result.avatar_url).to eq('ic')
    end
  end

  # ---------------------------------------------------------------------------
  # Badge from certifier_info
  # ---------------------------------------------------------------------------

  describe 'badge generation' do
    let(:unknown_type) { 'dW5rbm93blR5cGU=' }

    it 'sets badge_label from certifier name for unknown type' do
      result = parser.parse(cert_with_type(unknown_type, {}, certifier_info: certifier))
      expect(result.badge_label).to eq("#{unknown_type} certified by TrustCo")
    end

    it 'sets badge_icon_url from certifier icon_url' do
      result = parser.parse(cert_with_type(unknown_type, {}, certifier_info: certifier))
      expect(result.badge_icon_url).to eq('https://example.com/icon.png')
    end

    it 'falls back to default badge_label when certifier_info is nil' do
      result = parser.parse(cert_with_type(unknown_type, {}))
      expect(result.badge_label).to eq(default_identity.badge_label)
    end

    it 'falls back to default badge_icon_url when certifier_info is nil' do
      result = parser.parse(cert_with_type(unknown_type, {}))
      expect(result.badge_icon_url).to eq(default_identity.badge_icon_url)
    end

    it 'falls back to default badge_label when certifier name is empty string' do
      info   = BSV::Identity::CertifierInfo.new(name: '')
      result = parser.parse(cert_with_type(unknown_type, {}, certifier_info: info))
      expect(result.badge_label).to eq(default_identity.badge_label)
    end
  end

  # ---------------------------------------------------------------------------
  # Abbreviated key
  # ---------------------------------------------------------------------------

  describe 'abbreviated_key' do
    it 'abbreviates subjects of 10 or more characters' do
      cert = cert_with_type(types[:anyone], {}, subject: 'abcdefghij1234567890')
      expect(parser.parse(cert).abbreviated_key).to eq('abcdefghij...')
    end

    it 'does not truncate subjects shorter than 10 characters' do
      cert = cert_with_type(types[:anyone], {}, subject: 'abc')
      expect(parser.parse(cert).abbreviated_key).to eq('abc')
    end

    it 'returns empty string when subject is empty' do
      cert = cert_with_type(types[:anyone], {}, subject: '')
      expect(parser.parse(cert).abbreviated_key).to eq('')
    end

    it 'returns empty string when subject is nil' do
      cert = cert_with_type(types[:anyone], {}, subject: nil)
      expect(parser.parse(cert).abbreviated_key).to eq('')
    end
  end

  # ---------------------------------------------------------------------------
  # Empty string fields treated as absent
  # ---------------------------------------------------------------------------

  describe 'empty string fields treated as absent' do
    let(:unknown_type) { 'dW5rbm93blR5cGU=' }

    it 'skips empty name field and tries userName' do
      cert = cert_with_type(unknown_type, { 'name' => '', 'userName' => 'user_handle' })
      expect(parser.parse(cert).name).to eq('user_handle')
    end

    it 'skips empty userName and tries firstName+lastName' do
      cert = cert_with_type(unknown_type, { 'userName' => '', 'firstName' => 'Jo', 'lastName' => 'Bloggs' })
      expect(parser.parse(cert).name).to eq('Jo Bloggs')
    end

    it 'skips empty profilePhoto and falls back to avatar' do
      cert = cert_with_type(unknown_type, { 'profilePhoto' => '', 'avatar' => 'av_url' })
      expect(parser.parse(cert).avatar_url).to eq('av_url')
    end
  end

  # ---------------------------------------------------------------------------
  # identity_key is set from certificate subject
  # ---------------------------------------------------------------------------

  it 'sets identity_key to the certificate subject' do
    cert = cert_with_type(types[:anyone], {}, subject: 'mysubjectkey')
    expect(parser.parse(cert).identity_key).to eq('mysubjectkey')
  end
end
