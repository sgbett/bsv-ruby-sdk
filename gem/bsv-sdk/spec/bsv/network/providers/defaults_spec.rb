# frozen_string_literal: true

# rubocop:disable RSpec/DescribeClass
require 'spec_helper'

RSpec.describe 'BSV::Network::Providers defaults' do
  let(:http_client) { double('http_client') } # rubocop:disable RSpec/VerifiedDoubles

  # ── GorillaPool ───────────────────────────────────────────────────────────────

  describe 'GorillaPool.mainnet' do
    subject(:provider) { BSV::Network::Providers::GorillaPool.mainnet(http_client: http_client) }

    it 'returns a Provider named GorillaPool' do
      expect(provider.name).to eq('GorillaPool')
    end

    it 'registers three protocols' do
      expect(provider.protocols.length).to eq(3)
    end

    it 'registers Arcade as first protocol' do
      expect(provider.protocols[0]).to be_a(BSV::Network::Protocols::Arcade)
    end

    it 'registers Ordinals as second protocol' do
      expect(provider.protocols[1]).to be_a(BSV::Network::Protocols::Ordinals)
    end

    it 'registers JungleBus as third protocol' do
      expect(provider.protocols[2]).to be_a(BSV::Network::Protocols::JungleBus)
    end

    it 'serves :broadcast via Arcade' do
      expect(provider.protocol_for(:broadcast)).to be_a(BSV::Network::Protocols::Arcade)
    end

    it 'serves :get_merkle_path via Ordinals' do
      expect(provider.protocol_for(:get_merkle_path)).to be_a(BSV::Network::Protocols::Ordinals)
    end

    it 'serves :get_tx via Ordinals' do
      expect(provider.protocol_for(:get_tx)).to be_a(BSV::Network::Protocols::Ordinals)
    end

    it 'includes :broadcast in commands' do
      expect(provider.commands).to include(:broadcast)
    end

    it 'includes :current_height in commands (via JungleBus)' do
      expect(provider.commands).to include(:current_height)
    end

    it 'includes :get_tx in commands' do
      expect(provider.commands).to include(:get_tx)
    end

    it 'sets Arcade base_url to arcade.gorillapool.io' do
      expect(provider.protocols[0].base_url).to eq('https://arcade.gorillapool.io')
    end

    it 'sets Ordinals base_url to ordinals.gorillapool.io' do
      expect(provider.protocols[1].base_url).to eq('https://ordinals.gorillapool.io')
    end

    it 'forwards api_key to Arcade protocol' do
      p = BSV::Network::Providers::GorillaPool.mainnet(api_key: 'test-key', http_client: http_client)
      expect(p.protocols[0].api_key).to eq('test-key')
    end
  end

  describe 'GorillaPool.testnet' do
    subject(:provider) { BSV::Network::Providers::GorillaPool.testnet(http_client: http_client) }

    it 'returns a Provider named GorillaPool' do
      expect(provider.name).to eq('GorillaPool')
    end

    it 'registers two protocols' do
      expect(provider.protocols.length).to eq(2)
    end

    it 'registers Arcade as first protocol' do
      expect(provider.protocols[0]).to be_a(BSV::Network::Protocols::Arcade)
    end

    it 'registers JungleBus as second protocol' do
      expect(provider.protocols[1]).to be_a(BSV::Network::Protocols::JungleBus)
    end

    it 'serves :broadcast via Arcade' do
      expect(provider.protocol_for(:broadcast)).to be_a(BSV::Network::Protocols::Arcade)
    end

    it 'serves :current_height via JungleBus' do
      expect(provider.protocol_for(:current_height)).to be_a(BSV::Network::Protocols::JungleBus)
    end

    it 'includes :current_height in commands' do
      expect(provider.commands).to include(:current_height)
    end

    it 'sets Arcade base_url to testnet.arcade.gorillapool.io' do
      arcade = provider.protocols.find { |p| p.is_a?(BSV::Network::Protocols::Arcade) }
      expect(arcade.base_url).to eq('https://testnet.arcade.gorillapool.io')
    end

    it 'sets JungleBus base_url to testnet.junglebus.gorillapool.io' do
      jb = provider.protocols.find { |p| p.is_a?(BSV::Network::Protocols::JungleBus) }
      expect(jb.base_url).to eq('https://testnet.junglebus.gorillapool.io')
    end
  end

  # ── WhatsOnChain ──────────────────────────────────────────────────────────────

  describe 'WhatsOnChain.mainnet' do
    subject(:provider) { BSV::Network::Providers::WhatsOnChain.mainnet(http_client: http_client) }

    it 'returns a Provider named WhatsOnChain' do
      expect(provider.name).to eq('WhatsOnChain')
    end

    it 'registers one protocol' do
      expect(provider.protocols.length).to eq(1)
    end

    it 'registers WoCREST' do
      expect(provider.protocols[0]).to be_a(BSV::Network::Protocols::WoCREST)
    end

    it 'serves :broadcast via WoCREST' do
      expect(provider.protocol_for(:broadcast)).to be_a(BSV::Network::Protocols::WoCREST)
    end

    it 'serves :get_tx via WoCREST' do
      expect(provider.protocol_for(:get_tx)).to be_a(BSV::Network::Protocols::WoCREST)
    end

    it 'sets base_url to whatsonchain.com mainnet path' do
      expect(provider.protocols[0].base_url).to eq('https://api.whatsonchain.com/v1/bsv/main')
    end

    it 'forwards api_key to WoCREST protocol as auth: { api_key: }' do
      p = BSV::Network::Providers::WhatsOnChain.mainnet(api_key: 'woc-key', http_client: http_client)
      expect(p.protocols[0].auth).to eq({ api_key: 'woc-key' })
    end
  end

  describe 'WhatsOnChain.testnet' do
    subject(:provider) { BSV::Network::Providers::WhatsOnChain.testnet(http_client: http_client) }

    it 'returns a Provider named WhatsOnChain' do
      expect(provider.name).to eq('WhatsOnChain')
    end

    it 'registers WoCREST' do
      expect(provider.protocols[0]).to be_a(BSV::Network::Protocols::WoCREST)
    end

    it 'serves :broadcast via WoCREST' do
      expect(provider.protocol_for(:broadcast)).to be_a(BSV::Network::Protocols::WoCREST)
    end

    it 'sets base_url to whatsonchain.com testnet path' do
      expect(provider.protocols[0].base_url).to eq('https://api.whatsonchain.com/v1/bsv/test')
    end
  end

  # ── .default convenience methods ─────────────────────────────────────────────

  describe 'GorillaPool.default' do
    it 'returns mainnet provider when testnet: false (default)' do
      p = BSV::Network::Providers::GorillaPool.default(http_client: http_client)
      expect(p.protocols[0].base_url).to eq('https://arcade.gorillapool.io')
    end

    it 'returns testnet provider when testnet: true' do
      p = BSV::Network::Providers::GorillaPool.default(testnet: true, http_client: http_client)
      expect(p.protocols[0].base_url).to eq('https://testnet.arcade.gorillapool.io')
    end

    it 'forwards opts to the provider' do
      p = BSV::Network::Providers::GorillaPool.default(api_key: 'gp-key', http_client: http_client)
      expect(p.protocols[0].api_key).to eq('gp-key')
    end
  end

  describe 'WhatsOnChain.default' do
    it 'returns mainnet provider when testnet: false (default)' do
      p = BSV::Network::Providers::WhatsOnChain.default(http_client: http_client)
      expect(p.protocols[0].base_url).to eq('https://api.whatsonchain.com/v1/bsv/main')
    end

    it 'returns testnet provider when testnet: true' do
      p = BSV::Network::Providers::WhatsOnChain.default(testnet: true, http_client: http_client)
      expect(p.protocols[0].base_url).to eq('https://api.whatsonchain.com/v1/bsv/test')
    end
  end

  describe 'TAAL.default' do
    it 'returns mainnet provider when testnet: false (default)' do
      p = BSV::Network::Providers::TAAL.default(http_client: http_client)
      expect(p.protocols[0].base_url).to eq('https://arc.taal.com')
    end

    it 'returns testnet provider when testnet: true' do
      p = BSV::Network::Providers::TAAL.default(testnet: true, http_client: http_client)
      expect(p.protocols[0].base_url).to eq('https://arc-test.taal.com')
    end
  end

  # ── TAAL ──────────────────────────────────────────────────────────────────────

  describe 'TAAL.mainnet' do
    subject(:provider) { BSV::Network::Providers::TAAL.mainnet(http_client: http_client) }

    it 'returns a Provider named TAAL' do
      expect(provider.name).to eq('TAAL')
    end

    it 'registers two protocols' do
      expect(provider.protocols.length).to eq(2)
    end

    it 'registers ARC as first protocol' do
      expect(provider.protocols[0]).to be_a(BSV::Network::Protocols::ARC)
    end

    it 'registers TAALBinary as second protocol' do
      expect(provider.protocols[1]).to be_a(BSV::Network::Protocols::TAALBinary)
    end

    it 'serves :broadcast via ARC (first-registered wins)' do
      expect(provider.protocol_for(:broadcast)).to be_a(BSV::Network::Protocols::ARC)
    end

    it 'includes :broadcast in commands' do
      expect(provider.commands).to include(:broadcast)
    end

    it 'sets ARC base_url to arc.taal.com' do
      expect(provider.protocols[0].base_url).to eq('https://arc.taal.com')
    end

    it 'sets TAALBinary base_url to api.taal.com' do
      expect(provider.protocols[1].base_url).to eq('https://api.taal.com')
    end

    it 'forwards api_key to ARC protocol' do
      p = BSV::Network::Providers::TAAL.mainnet(api_key: 'taal-key', http_client: http_client)
      expect(p.protocols[0].api_key).to eq('taal-key')
    end

    it 'translates api_key to auth: { api_key: } for TAALBinary (no Bearer prefix)' do
      p = BSV::Network::Providers::TAAL.mainnet(api_key: 'taal-key', http_client: http_client)
      expect(p.protocols[1].auth).to eq({ api_key: 'taal-key' })
    end
  end

  describe 'TAAL.testnet' do
    subject(:provider) { BSV::Network::Providers::TAAL.testnet(http_client: http_client) }

    it 'returns a Provider named TAAL' do
      expect(provider.name).to eq('TAAL')
    end

    it 'registers one protocol' do
      expect(provider.protocols.length).to eq(1)
    end

    it 'registers ARC only' do
      expect(provider.protocols[0]).to be_a(BSV::Network::Protocols::ARC)
    end

    it 'sets ARC base_url to arc-test.taal.com' do
      expect(provider.protocols[0].base_url).to eq('https://arc-test.taal.com')
    end
  end
  # ── Auth and rate_limit wiring ────────────────────────────────────────────────

  describe 'DEFAULT_RATE_LIMIT constants' do
    it 'WhatsOnChain::DEFAULT_RATE_LIMIT is 3' do
      expect(BSV::Network::Providers::WhatsOnChain::DEFAULT_RATE_LIMIT).to eq(3)
    end

    it 'GorillaPool::DEFAULT_RATE_LIMIT is 3' do
      expect(BSV::Network::Providers::GorillaPool::DEFAULT_RATE_LIMIT).to eq(3)
    end

    it 'TAAL::DEFAULT_RATE_LIMIT is nil (tier-dependent)' do
      expect(BSV::Network::Providers::TAAL::DEFAULT_RATE_LIMIT).to be_nil
    end
  end

  describe 'WhatsOnChain — auth and rate_limit' do
    it 'provider.auth is :none when no auth supplied' do
      p = BSV::Network::Providers::WhatsOnChain.mainnet(http_client: http_client)
      expect(p.auth).to eq(:none)
    end

    it 'provider.rate_limit is DEFAULT_RATE_LIMIT when no rate_limit supplied' do
      p = BSV::Network::Providers::WhatsOnChain.mainnet(http_client: http_client)
      expect(p.rate_limit).to eq(BSV::Network::Providers::WhatsOnChain::DEFAULT_RATE_LIMIT)
    end

    it 'provider.auth reflects auth: hash' do
      p = BSV::Network::Providers::WhatsOnChain.mainnet(auth: { api_key: 'k' }, http_client: http_client)
      expect(p.auth).to eq({ api_key: 'k' })
    end

    it 'provider.authenticated? is true when auth: hash supplied' do
      p = BSV::Network::Providers::WhatsOnChain.mainnet(auth: { api_key: 'k' }, http_client: http_client)
      expect(p.authenticated?).to be(true)
    end

    it 'protocol receives auth: hash' do
      p = BSV::Network::Providers::WhatsOnChain.mainnet(auth: { api_key: 'k' }, http_client: http_client)
      expect(p.protocols[0].auth).to eq({ api_key: 'k' })
    end

    it 'rate_limit: override replaces default' do
      p = BSV::Network::Providers::WhatsOnChain.mainnet(rate_limit: 10, http_client: http_client)
      expect(p.rate_limit).to eq(10)
    end

    it 'auth: takes precedence over api_key:' do
      p = BSV::Network::Providers::WhatsOnChain.mainnet(
        auth: { api_key: 'explicit' }, api_key: 'legacy', http_client: http_client
      )
      expect(p.protocols[0].auth).to eq({ api_key: 'explicit' })
    end

    it 'legacy api_key: populates provider auth metadata' do
      p = BSV::Network::Providers::WhatsOnChain.mainnet(api_key: 'legacy-key', http_client: http_client)
      expect(p.auth).to eq({ api_key: 'legacy-key' })
      expect(p.authenticated?).to be(true)
    end
  end

  describe 'GorillaPool — auth and rate_limit' do
    it 'provider.auth is :none when no auth supplied' do
      p = BSV::Network::Providers::GorillaPool.mainnet(http_client: http_client)
      expect(p.auth).to eq(:none)
    end

    it 'provider.rate_limit is DEFAULT_RATE_LIMIT when no rate_limit supplied' do
      p = BSV::Network::Providers::GorillaPool.mainnet(http_client: http_client)
      expect(p.rate_limit).to eq(BSV::Network::Providers::GorillaPool::DEFAULT_RATE_LIMIT)
    end

    it 'provider.auth reflects auth: hash' do
      p = BSV::Network::Providers::GorillaPool.mainnet(auth: { bearer: 'tok' }, http_client: http_client)
      expect(p.auth).to eq({ bearer: 'tok' })
    end

    it 'provider.authenticated? is true when auth: supplied' do
      p = BSV::Network::Providers::GorillaPool.mainnet(auth: { bearer: 'tok' }, http_client: http_client)
      expect(p.authenticated?).to be(true)
    end

    it 'forwards auth: to Arcade protocol' do
      p = BSV::Network::Providers::GorillaPool.mainnet(auth: { bearer: 'tok' }, http_client: http_client)
      expect(p.protocols[0].auth).to eq({ bearer: 'tok' })
    end

    it 'forwards auth: to Ordinals protocol' do
      p = BSV::Network::Providers::GorillaPool.mainnet(auth: { bearer: 'tok' }, http_client: http_client)
      expect(p.protocols[1].auth).to eq({ bearer: 'tok' })
    end

    it 'forwards auth: to JungleBus protocol' do
      p = BSV::Network::Providers::GorillaPool.mainnet(auth: { bearer: 'tok' }, http_client: http_client)
      expect(p.protocols[2].auth).to eq({ bearer: 'tok' })
    end

    it 'rate_limit: override replaces default' do
      p = BSV::Network::Providers::GorillaPool.mainnet(rate_limit: 50, http_client: http_client)
      expect(p.rate_limit).to eq(50)
    end

    it 'legacy api_key: populates provider auth metadata as bearer' do
      p = BSV::Network::Providers::GorillaPool.mainnet(api_key: 'gp-key', http_client: http_client)
      expect(p.auth).to eq({ bearer: 'gp-key' })
      expect(p.authenticated?).to be(true)
    end

    it 'testnet forwards auth: to all protocols' do
      p = BSV::Network::Providers::GorillaPool.testnet(auth: { bearer: 'tok' }, http_client: http_client)
      p.protocols.each do |proto|
        expect(proto.auth).to eq({ bearer: 'tok' })
      end
    end
  end

  describe 'TAAL — auth and rate_limit' do
    it 'provider.auth is :none when no auth supplied' do
      p = BSV::Network::Providers::TAAL.mainnet(http_client: http_client)
      expect(p.auth).to eq(:none)
    end

    it 'provider.rate_limit is nil (DEFAULT_RATE_LIMIT) when no rate_limit supplied' do
      p = BSV::Network::Providers::TAAL.mainnet(http_client: http_client)
      expect(p.rate_limit).to be_nil
    end

    it 'provider.auth reflects auth: hash' do
      p = BSV::Network::Providers::TAAL.mainnet(auth: { api_key: 'taal-k' }, http_client: http_client)
      expect(p.auth).to eq({ api_key: 'taal-k' })
    end

    it 'provider.authenticated? is true when auth: supplied' do
      p = BSV::Network::Providers::TAAL.mainnet(auth: { api_key: 'taal-k' }, http_client: http_client)
      expect(p.authenticated?).to be(true)
    end

    it 'forwards auth: to ARC protocol' do
      p = BSV::Network::Providers::TAAL.mainnet(auth: { api_key: 'taal-k' }, http_client: http_client)
      expect(p.protocols[0].auth).to eq({ api_key: 'taal-k' })
    end

    it 'forwards auth: to TAALBinary protocol' do
      p = BSV::Network::Providers::TAAL.mainnet(auth: { api_key: 'taal-k' }, http_client: http_client)
      expect(p.protocols[1].auth).to eq({ api_key: 'taal-k' })
    end

    it 'rate_limit: override replaces default' do
      p = BSV::Network::Providers::TAAL.mainnet(rate_limit: 25, http_client: http_client)
      expect(p.rate_limit).to eq(25)
    end

    it 'legacy api_key: populates provider auth metadata as bearer' do
      p = BSV::Network::Providers::TAAL.mainnet(api_key: 'taal-key', http_client: http_client)
      expect(p.auth).to eq({ bearer: 'taal-key' })
      expect(p.authenticated?).to be(true)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
