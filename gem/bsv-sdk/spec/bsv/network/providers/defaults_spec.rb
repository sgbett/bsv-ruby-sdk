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

    it 'registers ARC as first protocol' do
      expect(provider.protocols[0]).to be_a(BSV::Network::Protocols::ARC)
    end

    it 'registers Chaintracks as second protocol' do
      expect(provider.protocols[1]).to be_a(BSV::Network::Protocols::Chaintracks)
    end

    it 'registers Ordinals as third protocol' do
      expect(provider.protocols[2]).to be_a(BSV::Network::Protocols::Ordinals)
    end

    it 'serves :broadcast via ARC' do
      expect(provider.protocol_for(:broadcast)).to be_a(BSV::Network::Protocols::ARC)
    end

    it 'serves :current_height via Chaintracks' do
      expect(provider.protocol_for(:current_height)).to be_a(BSV::Network::Protocols::Chaintracks)
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

    it 'includes :current_height in commands' do
      expect(provider.commands).to include(:current_height)
    end

    it 'includes :get_tx in commands' do
      expect(provider.commands).to include(:get_tx)
    end

    it 'sets ARC base_url to arcade.gorillapool.io' do
      expect(provider.protocols[0].base_url).to eq('https://arcade.gorillapool.io')
    end

    it 'sets Chaintracks base_url to arcade.gorillapool.io' do
      expect(provider.protocols[1].base_url).to eq('https://arcade.gorillapool.io')
    end

    it 'sets Ordinals base_url to ordinals.gorillapool.io' do
      expect(provider.protocols[2].base_url).to eq('https://ordinals.gorillapool.io')
    end

    it 'forwards api_key to ARC protocol' do
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

    it 'registers ARC and Chaintracks' do
      classes = provider.protocols.map(&:class)
      expect(classes).to include(BSV::Network::Protocols::ARC, BSV::Network::Protocols::Chaintracks)
    end

    it 'serves :broadcast via ARC' do
      expect(provider.protocol_for(:broadcast)).to be_a(BSV::Network::Protocols::ARC)
    end

    it 'serves :current_height via Chaintracks' do
      expect(provider.protocol_for(:current_height)).to be_a(BSV::Network::Protocols::Chaintracks)
    end

    it 'sets ARC base_url to testnet.arcade.gorillapool.io' do
      arc = provider.protocols.find { |p| p.is_a?(BSV::Network::Protocols::ARC) }
      expect(arc.base_url).to eq('https://testnet.arcade.gorillapool.io')
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

    it 'forwards api_key to WoCREST protocol' do
      p = BSV::Network::Providers::WhatsOnChain.mainnet(api_key: 'woc-key', http_client: http_client)
      expect(p.protocols[0].api_key).to eq('woc-key')
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

    it 'forwards api_key to both protocols' do
      p = BSV::Network::Providers::TAAL.mainnet(api_key: 'taal-key', http_client: http_client)
      expect(p.protocols[0].api_key).to eq('taal-key')
      expect(p.protocols[1].api_key).to eq('taal-key')
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
end
# rubocop:enable RSpec/DescribeClass
