# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::MCP::Config do
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

    it 'accepts the alias main for mainnet' do
      with_env('BSV_NETWORK' => 'main') do
        expect(described_class.new.network).to eq('mainnet')
      end
    end

    it 'accepts the alias test for testnet' do
      with_env('BSV_NETWORK' => ' Test ') do
        expect(described_class.new.network).to eq('testnet')
      end
    end

    it 'treats a blank value as unset' do
      with_env('BSV_NETWORK' => '  ') do
        expect(described_class.new.network).to eq('mainnet')
      end
    end

    it 'raises for unknown network values, naming the variable and the allowed values' do
      with_env('BSV_NETWORK' => 'unknown') do
        expect { described_class.new }
          .to raise_error(ArgumentError, /BSV_NETWORK must be one of: mainnet, testnet, main, test/)
      end
    end

    it 'raises for an unknown keyword network' do
      expect { described_class.new(network: 'regtest') }.to raise_error(ArgumentError, /BSV_NETWORK/)
    end
  end

  describe 'ARC env vars' do
    it 'reads BSV_ARC_URL' do
      with_env('BSV_ARC_URL' => 'https://arc.example.com') do
        expect(described_class.new.arc_url).to eq('https://arc.example.com')
      end
    end

    it 'reads BSV_ARC_API_KEY' do
      with_env('BSV_ARC_URL' => 'https://arc.example.com', 'BSV_ARC_API_KEY' => 'secret') do
        expect(described_class.new.arc_api_key).to eq('secret')
      end
    end

    it 'treats blank BSV_ARC_URL and BSV_ARC_API_KEY as unset' do
      with_env('BSV_ARC_URL' => '', 'BSV_ARC_API_KEY' => '   ') do
        config = described_class.new
        expect([config.arc_url, config.arc_api_key]).to eq([nil, nil])
      end
    end

    it 'treats blank keyword values as unset' do
      with_env('BSV_ARC_URL' => 'https://env.example.com') do
        expect(described_class.new(arc_url: ' ').arc_url).to eq('https://env.example.com')
      end
    end

    it 'warns, without echoing the key, when a key is set without a URL' do
      with_env('BSV_ARC_URL' => nil, 'BSV_ARC_API_KEY' => 'hunter2') do
        expect { described_class.new }
          .to output(/BSV_ARC_API_KEY is set without BSV_ARC_URL/).to_stderr
        expect { described_class.new }.not_to output(/hunter2/).to_stderr
      end
    end

    it 'accepts http for loopback hosts' do
      %w[http://localhost:8080 http://127.0.0.1:9090/arc http://[::1]:3000].each do |url|
        expect(described_class.new(arc_url: url).arc_url).to eq(url)
      end
    end

    describe 'URL validation' do
      [
        'http://arc.example.com',
        'ftp://arc.example.com',
        'https://',
        'arc.example.com',
        'https://user:pass@arc.example.com',
        'https://arc.example.com/?k=v',
        'https://arc.example.com/path#frag',
        'https://arc.example.com?',
        'https://arc.example.com:bad',
        'https://exa mple.com'
      ].each do |url|
        it "rejects #{url.inspect} without echoing it" do
          expect { described_class.new(arc_url: url, arc_api_key: 'hunter2') }
            .to raise_error(ArgumentError) { |e|
              expect(e.message).to include('BSV_ARC_URL')
              expect(e.message).not_to include(url)
              expect(e.message).not_to include('hunter2')
            }
        end
      end
    end

    it 'keeps the key out of inspect' do
      config = described_class.new(arc_url: 'https://arc.example.com', arc_api_key: 'hunter2')
      expect(config.inspect).not_to include('hunter2')
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
