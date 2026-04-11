# frozen_string_literal: true

RSpec.describe BSV::Identity::Constants do
  subject(:constants) { described_class }

  describe 'TOPIC' do
    it 'identifies the identity overlay topic' do
      expect(constants::TOPIC).to eq('tm_identity')
    end
  end

  describe 'SERVICE' do
    it 'identifies the identity lookup service' do
      expect(constants::SERVICE).to eq('ls_identity')
    end
  end

  describe 'KNOWN_IDENTITY_TYPES' do
    subject(:types) { constants::KNOWN_IDENTITY_TYPES }

    it 'contains all 9 recognised certificate types' do
      expect(types.size).to eq(9)
    end

    it 'is frozen' do
      expect(types).to be_frozen
    end

    it 'includes x_cert with correct Base64 type ID' do
      expect(types[:x_cert]).to eq('vdDWvftf1H+5+ZprUw123kjHlywH+v20aPQTuXgMpNc=')
    end

    it 'includes discord_cert with correct Base64 type ID' do
      expect(types[:discord_cert]).to eq('2TgqRC35B1zehGmB21xveZNc7i5iqHc0uxMb+1NMPW4=')
    end

    it 'includes phone_cert with correct Base64 type ID' do
      expect(types[:phone_cert]).to eq('mffUklUzxbHr65xLohn0hRL0Tq2GjW1GYF/OPfzqJ6A=')
    end

    it 'includes email_cert with correct Base64 type ID' do
      expect(types[:email_cert]).to eq('exOl3KM0dIJ04EW5pZgbZmPag6MdJXd3/a1enmUU/BA=')
    end

    it 'includes identi_cert with correct Base64 type ID' do
      expect(types[:identi_cert]).to eq('z40BOInXkI8m7f/wBrv4MJ09bZfzZbTj2fJqCtONqCY=')
    end

    it 'includes registrant with correct Base64 type ID' do
      expect(types[:registrant]).to eq('YoPsbfR6YQczjzPdHCoGC7nJsOdPQR50+SYqcWpJ0y0=')
    end

    it 'includes cool_cert with correct Base64 type ID' do
      expect(types[:cool_cert]).to eq('AGfk/WrT1eBDXpz3mcw386Zww2HmqcIn3uY6x4Af1eo=')
    end

    it 'includes anyone with correct Base64 type ID' do
      expect(types[:anyone]).to eq('mfkOMfLDQmrr3SBxBQ5WeE+6Hy3VJRFq6w4A5Ljtlis=')
    end

    it 'includes self with correct Base64 type ID' do
      expect(types[:self]).to eq('Hkge6X5JRxt1cWXtHLCrSTg6dCVTxjQJJ48iOYd7n3g=')
    end

    it 'values decode to 32 bytes each' do
      require 'base64'
      types.each_value do |b64|
        expect(Base64.decode64(b64).bytesize).to eq(32)
      end
    end
  end

  describe 'DEFAULT_IDENTITY' do
    subject(:default_id) { constants::DEFAULT_IDENTITY }

    it 'is a DisplayableIdentity' do
      expect(default_id).to be_a(BSV::Identity::DisplayableIdentity)
    end

    it 'is frozen' do
      expect(default_id).to be_frozen
    end

    it 'has fallback name' do
      expect(default_id.name).to eq('Unknown Identity')
    end

    it 'has a default avatar URL' do
      expect(default_id.avatar_url).to eq('XUUB8bbn9fEthk15Ge3zTQXypUShfC94vFjp65v7u5CQ8qkpxzst')
    end

    it 'has empty abbreviated_key' do
      expect(default_id.abbreviated_key).to eq('')
    end

    it 'has empty identity_key' do
      expect(default_id.identity_key).to eq('')
    end

    it 'has a default badge icon URL' do
      expect(default_id.badge_icon_url).to eq('XUUV39HVPkpmMzYNTx7rpKzJvXfeiVyQWg2vfSpjBAuhunTCA9uG')
    end

    it 'has a default badge label indicating unverified status' do
      expect(default_id.badge_label).to eq('Not verified by anyone you trust.')
    end

    it 'has a default badge click URL pointing to documentation' do
      expect(default_id.badge_click_url).to eq('https://projectbabbage.com/docs/unknown-identity')
    end
  end

  describe 'BSV::Identity::ClientOptions::DEFAULT' do
    subject(:default_opts) { BSV::Identity::ClientOptions::DEFAULT }

    it 'is a ClientOptions instance' do
      expect(default_opts).to be_a(BSV::Identity::ClientOptions)
    end

    it 'is frozen' do
      expect(default_opts).to be_frozen
    end

    it 'uses identity protocol with security level 1' do
      expect(default_opts.protocol_id).to eq([1, 'identity'])
    end

    it 'uses key ID 1' do
      expect(default_opts.key_id).to eq('1')
    end

    it 'uses token amount of 1 satoshi' do
      expect(default_opts.token_amount).to eq(1)
    end

    it 'uses output index 0' do
      expect(default_opts.output_index).to eq(0)
    end
  end

  describe 'autoload' do
    it 'is accessible via BSV::Identity::Constants' do
      expect(described_class).to be_a(Module)
    end

    it 'loads DisplayableIdentity via BSV::Identity' do
      expect(BSV::Identity::DisplayableIdentity).to be_a(Class)
    end

    it 'loads ClientOptions via BSV::Identity' do
      expect(BSV::Identity::ClientOptions).to be_a(Class)
    end
  end
end
