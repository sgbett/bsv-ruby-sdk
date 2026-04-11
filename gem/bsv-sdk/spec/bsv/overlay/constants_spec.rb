# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'BSV::Overlay::Constants' do
  subject(:constants) { BSV::Overlay::Constants }

  describe 'protocol identifiers' do
    it 'defines PROTOCOL_SHIP as SHIP' do
      expect(constants::PROTOCOL_SHIP).to eq('SHIP')
    end

    it 'defines PROTOCOL_SLAP as SLAP' do
      expect(constants::PROTOCOL_SLAP).to eq('SLAP')
    end

    it 'defines PROTOCOL_ID_SHIP' do
      expect(constants::PROTOCOL_ID_SHIP).to eq('Service Host Interconnect')
    end

    it 'defines PROTOCOL_ID_SLAP' do
      expect(constants::PROTOCOL_ID_SLAP).to eq('Service Lookup Availability')
    end
  end

  describe 'SLAP tracker URLs' do
    it 'includes US BSVA cluster in mainnet trackers' do
      expect(constants::DEFAULT_SLAP_TRACKERS).to include('https://overlay-us-1.bsvb.tech')
    end

    it 'includes EU BSVA cluster in mainnet trackers' do
      expect(constants::DEFAULT_SLAP_TRACKERS).to include('https://overlay-eu-1.bsvb.tech')
    end

    it 'includes AP BSVA cluster in mainnet trackers' do
      expect(constants::DEFAULT_SLAP_TRACKERS).to include('https://overlay-ap-1.bsvb.tech')
    end

    it 'includes Babbage primary service in mainnet trackers' do
      expect(constants::DEFAULT_SLAP_TRACKERS).to include('https://users.bapp.dev')
    end

    it 'includes Babbage testnet service in testnet trackers' do
      expect(constants::DEFAULT_TESTNET_SLAP_TRACKERS).to include('https://testnet-users.bapp.dev')
    end

    it 'freezes the mainnet tracker array' do
      expect(constants::DEFAULT_SLAP_TRACKERS).to be_frozen
    end

    it 'freezes the testnet tracker array' do
      expect(constants::DEFAULT_TESTNET_SLAP_TRACKERS).to be_frozen
    end
  end

  describe 'NETWORK_PRESETS' do
    it 'maps mainnet to the mainnet SLAP trackers' do
      expect(constants::NETWORK_PRESETS['mainnet']).to eq(constants::DEFAULT_SLAP_TRACKERS)
    end

    it 'maps testnet to the testnet SLAP trackers' do
      expect(constants::NETWORK_PRESETS['testnet']).to eq(constants::DEFAULT_TESTNET_SLAP_TRACKERS)
    end

    it 'is frozen' do
      expect(constants::NETWORK_PRESETS).to be_frozen
    end
  end
end
