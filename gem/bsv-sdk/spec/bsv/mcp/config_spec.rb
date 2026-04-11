# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::MCP::Config do
  # Helper to temporarily set env vars for the duration of a block.
  def with_env(vars)
    old = vars.keys.to_h { |k| [k, ENV.fetch(k, nil)] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV.store(k, v) }
    yield
  ensure
    old.each { |k, v| v.nil? ? ENV.delete(k) : ENV.store(k, v) }
  end

  describe 'defaults' do
    subject(:config) do
      with_env('BSV_NETWORK' => nil, 'BSV_ARC_URL' => nil, 'BSV_ARC_API_KEY' => nil) do
        described_class.new
      end
    end

    it 'defaults network to mainnet' do
      expect(config.network).to eq('mainnet')
    end

    it 'reports mainnet?' do
      expect(config.mainnet?).to be true
    end

    it 'reports testnet? as false' do
      expect(config.testnet?).to be false
    end

    it 'has nil arc_url by default' do
      expect(config.arc_url).to be_nil
    end

    it 'has nil arc_api_key by default' do
      expect(config.arc_api_key).to be_nil
    end
  end

  describe 'BSV_NETWORK env var' do
    it 'accepts mainnet' do
      with_env('BSV_NETWORK' => 'mainnet') do
        expect(described_class.new.network).to eq('mainnet')
      end
    end

    it 'sets network to testnet' do
      with_env('BSV_NETWORK' => 'testnet') do
        expect(described_class.new.network).to eq('testnet')
      end
    end

    it 'reports testnet? true for testnet' do
      with_env('BSV_NETWORK' => 'testnet') do
        expect(described_class.new.testnet?).to be true
      end
    end

    it 'reports mainnet? false for testnet' do
      with_env('BSV_NETWORK' => 'testnet') do
        expect(described_class.new.mainnet?).to be false
      end
    end

    it 'normalises to lowercase' do
      with_env('BSV_NETWORK' => 'MAINNET') do
        expect(described_class.new.network).to eq('mainnet')
      end
    end

    it 'warns for unknown network values' do
      with_env('BSV_NETWORK' => 'unknown') do
        expect { described_class.new }.to output(/unknown network/).to_stderr
      end
    end

    it 'falls back to mainnet for unknown network values' do
      with_env('BSV_NETWORK' => 'unknown') do
        expect(described_class.new.network).to eq('mainnet')
      end
    end
  end

  describe 'ARC env vars' do
    it 'reads BSV_ARC_URL' do
      with_env('BSV_ARC_URL' => 'https://arc.example.com') do
        expect(described_class.new.arc_url).to eq('https://arc.example.com')
      end
    end

    it 'reads BSV_ARC_API_KEY' do
      with_env('BSV_ARC_API_KEY' => 'secret') do
        expect(described_class.new.arc_api_key).to eq('secret')
      end
    end
  end

  describe 'keyword overrides' do
    it 'prefers keyword network over env var' do
      with_env('BSV_NETWORK' => 'testnet') do
        config = described_class.new(network: 'mainnet')
        expect(config.network).to eq('mainnet')
      end
    end

    it 'prefers keyword arc_url over env var' do
      with_env('BSV_ARC_URL' => 'https://env.example.com') do
        config = described_class.new(arc_url: 'https://override.example.com')
        expect(config.arc_url).to eq('https://override.example.com')
      end
    end
  end
end
