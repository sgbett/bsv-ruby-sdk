# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module BSV
  module Network
    module Providers
      # WhatsOnChain provider implementing core BSV network commands.
      #
      # Implements {BSV::Network::Provider} for the WhatsOnChain API, covering
      # transaction lookup, UTXO fetching, chain height, and Merkle root validation.
      #
      # @example
      #   provider = BSV::Network::Providers::WhatsOnChain.new(network: :main)
      #   result = provider.call(:get_tx, 'abc123...')
      #   result.data if result.success?
      class WhatsOnChain < Provider
        provides :get_tx, :get_utxos, :current_height, :valid_root

        BASE_URL = 'https://api.whatsonchain.com'

        NETWORKS = {
          main: 'main',
          mainnet: 'main',
          test: 'test',
          testnet: 'test',
          stn: 'stn'
        }.freeze

        # @param network [Symbol] :main, :mainnet, :test, :testnet, or :stn
        # @param api_key [String, nil] optional WoC API key sent in Authorization header
        # @param http_client [#request, nil] injectable HTTP client for testing
        def initialize(network: :main, api_key: nil, http_client: nil)
          super(http_client: http_client)
          @network = NETWORKS.fetch(network) { raise ArgumentError, "unknown network: #{network}" }
          @api_key = api_key
        end

        # Fetch a raw transaction by TXID.
        #
        # @param txid [String] transaction ID (hex)
        # @return [Result::Success<String>, Result::NotFound, Result::Error]
        def call_get_tx(txid)
          response = get("/v1/bsv/#{@network}/tx/#{txid}/hex")
          return response if response.is_a?(Result::Error) || response.is_a?(Result::NotFound)

          success(response.body.strip)
        end

        # Fetch all unspent outputs for an address.
        #
        # @param address [String] BSV address
        # @return [Result::Success<Array>, Result::Error]
        def call_get_utxos(address)
          response = get("/v1/bsv/#{@network}/address/#{address}/unspent", not_found_returns_empty: true)
          return response if response.is_a?(Result::Success) || response.is_a?(Result::Error)

          body = parse_json(response.body)
          return body if body.is_a?(Result::Error)

          utxos = body.map do |entry|
            {
              tx_hash: entry['tx_hash'],
              tx_pos: entry['tx_pos'],
              satoshis: entry['value'],
              height: entry['height']
            }
          end

          success(utxos)
        end

        # Return the current best-chain block height.
        #
        # @return [Result::Success<Integer>, Result::Error]
        def call_current_height
          response = get("/v1/bsv/#{@network}/chain/info", not_found_returns_empty: false)
          return response if response.is_a?(Result::Error)

          body = parse_json(response.body)
          return body if body.is_a?(Result::Error)

          height = body['blocks']
          return error('chain/info response missing "blocks" field', retryable: false) if height.nil?

          success(height)
        end

        # Verify that a Merkle root matches the block header at a given height.
        #
        # Performs a case-insensitive comparison against the merkleroot field
        # returned by the WoC block header endpoint.
        #
        # @param root [String] Merkle root as a hex string
        # @param height [Integer] block height
        # @return [Result::Success<Boolean>, Result::NotFound, Result::Error]
        def call_valid_root(root, height)
          response = get("/v1/bsv/#{@network}/block/#{height}/header")
          return response if response.is_a?(Result::Error) || response.is_a?(Result::NotFound)

          body = parse_json(response.body)
          return body if body.is_a?(Result::Error)

          merkle_root = body['merkleroot']
          return error('block header response missing "merkleroot" field', retryable: false) if merkle_root.nil?

          success(merkle_root.downcase == root.downcase)
        end

        private

        # Perform a GET request to the given path.
        #
        # @param path [String] API path (including leading slash)
        # @param not_found_returns_empty [Boolean, nil]
        #   - true  → 404 returns success([])
        #   - false → 404 returns error
        #   - nil   → 404 returns not_found (default)
        # @return [Net::HTTPResponse, Result::Success, Result::NotFound, Result::Error]
        def get(path, not_found_returns_empty: nil)
          uri = URI("#{BASE_URL}#{path}")
          request = Net::HTTP::Get.new(uri)
          request['Authorization'] = @api_key if @api_key

          response = execute(uri, request)
          code = response.code.to_i

          case code
          when 200..299
            response
          when 404
            handle_not_found(not_found_returns_empty)
          when 429, 500..599
            error("HTTP #{code}: #{response.body&.strip}", retryable: true)
          else
            error("HTTP #{code}: #{response.body&.strip}", retryable: false)
          end
        end

        def handle_not_found(not_found_returns_empty)
          case not_found_returns_empty
          when true
            success([])
          when false
            error('HTTP 404: not found', retryable: false)
          else
            not_found
          end
        end

        def execute(uri, request)
          if @http_client
            @http_client.request(uri, request)
          else
            Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
              http.request(request)
            end
          end
        end

        def parse_json(body)
          JSON.parse(body)
        rescue JSON::ParserError => e
          error("JSON parse error: #{e.message}", retryable: false)
        end
      end
    end
  end
end
