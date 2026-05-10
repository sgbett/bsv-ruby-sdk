# frozen_string_literal: true

require 'spec_helper'
require 'net/http'
require 'json'
require 'uri'

# Integration tests verifying the custom Protocol/Provider DSL against a live
# chaintracks-cloudflare worker:
#   https://github.com/Calhooon/chaintracks-cloudflare
#
# The focus is on proving that our Protocol endpoint DSL, response handlers,
# path interpolation, and Provider dispatch all work end-to-end against a
# real HTTP service. The specific chaintracks responses are incidental — we
# check structure, not values, for anything that varies over time.
#
# The worker only retains a recent window of headers (~50 blocks plus
# genesis), so tests use a height near the tip rather than a fixed block.
#
# Run with:
#   bundle exec rspec --tag chaintracks_live
#
# Optionally set a custom endpoint:
#   CHAINTRACKS_URL='https://my-worker.example.com' bundle exec rspec --tag chaintracks_live
RSpec.describe 'Custom Provider: chaintracks-cloudflare', :chaintracks_live do
  let(:worker_url) do
    ENV.fetch('CHAINTRACKS_URL', 'https://rust-chaintracks.dev-a3e.workers.dev')
  end

  # -------------------------------------------------------------------
  # Define a custom Protocol subclass using the DSL — this is the code
  # under test, exercising endpoint declaration and response handlers.
  # -------------------------------------------------------------------

  let(:protocol_class) do
    Class.new(BSV::Network::Protocol) do
      # :raw response (default) — returns body string
      endpoint :get_chain,    :get, '/getChain',    response: :json

      # :json response — returns parsed Hash
      endpoint :get_info,     :get, '/getInfo',     response: :json

      # Custom lambda response handlers — the worker wraps values in
      # { "status": "success", "value": ... } so we unwrap here
      endpoint :current_height, :get, '/currentHeight', response: lambda { |body|
        JSON.parse(body)['value']
      }

      endpoint :find_header, :get, '/findHeaderHexForHeight?height={height}', response: lambda { |body|
        JSON.parse(body)['value']
      }

      endpoint :find_header_by_hash, :get, '/findHeaderHexForBlockHash?hash={hash}', response: lambda { |body|
        JSON.parse(body)['value']
      }

      endpoint :chain_tip_hash, :get, '/findChainTipHashHex', response: lambda { |body|
        JSON.parse(body)['value']
      }

      endpoint :chain_tip_header, :get, '/findChainTipHeaderHex', response: lambda { |body|
        JSON.parse(body)['value']
      }

      endpoint :get_headers, :get, '/getHeaders?height={height}&count={count}', response: lambda { |body|
        JSON.parse(body)['value']
      }

      endpoint :is_valid_root, :get, '/isValidRootForHeight?root={root}&height={height}', response: lambda { |body|
        JSON.parse(body)['value']
      }
    end
  end

  # -------------------------------------------------------------------
  # Wire it into a Provider — tests Provider dispatch, command indexing,
  # and capability matrix with a single-protocol provider.
  # -------------------------------------------------------------------

  let(:provider) do
    klass = protocol_class
    url   = worker_url
    BSV::Network::Provider.new('ChaintracksCloudflare') do |p|
      p.protocol klass, base_url: url
    end
  end

  # A confirmed height within the worker's retention window
  let(:confirmed_height) do
    result = provider.call(:current_height)
    result.data - 10
  end

  # -------------------------------------------------------------------
  # Protocol DSL: endpoint declaration and class introspection
  # -------------------------------------------------------------------

  describe 'Protocol DSL' do
    it 'registers all declared endpoints as commands' do
      expected = %i[get_chain get_info current_height find_header
                    find_header_by_hash chain_tip_hash chain_tip_header
                    get_headers is_valid_root]
      expect(protocol_class.commands).to eq(Set.new(expected))
    end

    it 'exposes endpoint definitions for introspection' do
      defn = protocol_class.endpoints[:current_height]
      expect(defn[:method]).to eq(:get)
      expect(defn[:path]).to eq('/currentHeight')
      expect(defn[:response]).to respond_to(:call)
    end
  end

  # -------------------------------------------------------------------
  # Provider: dispatch, command index, capability matrix
  # -------------------------------------------------------------------

  describe 'Provider dispatch' do
    it 'lists all commands from the registered protocol' do
      expect(provider.commands).to eq(protocol_class.commands)
    end

    it 'returns a capability matrix mapping protocol to commands' do
      matrix = provider.capability_matrix
      expect(matrix.size).to eq(1)
      expect(matrix.values.first).to include(:current_height, :find_header)
    end

    it 'raises ArgumentError for an unknown command' do
      expect { provider.call(:nonexistent) }
        .to raise_error(ArgumentError, /does not provide command/)
    end
  end

  # -------------------------------------------------------------------
  # End-to-end: Result types and response handlers against live HTTP
  # -------------------------------------------------------------------

  describe 'Result handling' do
    it 'returns Success with :json handler' do
      result = provider.call(:get_info)
      expect(result).to be_http_success
      expect(result.data).to be_a(Hash)
      expect(result.data['status']).to eq('success')
    end

    it 'returns Success with lambda handler (unwrapped integer)' do
      result = provider.call(:current_height)
      expect(result).to be_http_success
      expect(result.data).to be_a(Integer)
      expect(result.data).to be > 900_000
    end

    it 'returns Success with lambda handler (unwrapped hash)' do
      result = provider.call(:find_header, height: confirmed_height)
      expect(result).to be_http_success
      expect(result.data).to be_a(Hash)
      expect(result.data['height']).to eq(confirmed_height)
      expect(result.data['merkleRoot'].length).to eq(64)
    end

    it 'returns Success with lambda handler (unwrapped string)' do
      result = provider.call(:chain_tip_hash)
      expect(result).to be_http_success
      expect(result.data).to be_a(String)
      expect(result.data.length).to eq(64)
    end

    it 'returns Success with lambda handler (unwrapped boolean)' do
      header = provider.call(:find_header, height: confirmed_height)
      root = header.data['merkleRoot']

      result = provider.call(:is_valid_root, root: root, height: confirmed_height)
      expect(result).to be_http_success
      expect(result.data).to be(true)
    end

    it 'interpolates multiple path parameters' do
      result = provider.call(:get_headers, height: confirmed_height, count: 3)
      expect(result).to be_http_success
      # 3 headers x 80 bytes x 2 hex chars = 480
      expect(result.data).to be_a(String)
      expect(result.data.length).to eq(480)
    end

    it 'handles NotFound for an out-of-range height' do
      result = provider.call(:find_header, height: 999_999_999)
      expect(result).not_to be_http_success
    end
  end

  # -------------------------------------------------------------------
  # Cross-verification: our WhatsOnChain ChainTracker agrees with the
  # custom provider's data — proves both implementations read the same
  # chain.
  # -------------------------------------------------------------------

  describe 'cross-verification with SDK ChainTracker' do
    let(:woc_tracker) do
      BSV::Transaction::ChainTrackers::WhatsOnChain.new(network: :main)
    end

    it 'heights agree within 2 blocks' do
      worker_height = provider.call(:current_height).data
      woc_height    = woc_tracker.current_height
      expect(worker_height).to be_within(2).of(woc_height)
    end

    it 'merkle root from custom provider validates via WhatsOnChain' do
      header = provider.call(:find_header, height: confirmed_height)
      root   = header.data['merkleRoot']
      expect(woc_tracker.valid_root_for_height?(root, confirmed_height)).to be(true)
    end
  end
end
