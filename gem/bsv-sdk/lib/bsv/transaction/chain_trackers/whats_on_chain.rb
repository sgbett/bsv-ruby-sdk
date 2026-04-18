# frozen_string_literal: true

require 'net/http'

module BSV
  module Transaction
    module ChainTrackers
      # Chain tracker that verifies merkle roots using the WhatsOnChain API.
      #
      # Delegates all HTTP communication to {BSV::Network::Protocols::WoCREST}.
      # The constructor signature and {ChainTracker} contract are preserved.
      #
      # Note: the WoC API key is sent as a raw +Authorization+ header value
      # (not Bearer-prefixed) to match the existing WoC API convention.
      #
      # @example
      #   tracker = BSV::Transaction::ChainTrackers::WhatsOnChain.new
      #   tracker.valid_root_for_height?('abcd...', 800_000)
      class WhatsOnChain < ChainTracker
        NETWORKS = {
          main: 'main',
          mainnet: 'main',
          test: 'test',
          testnet: 'test',
          stn: 'stn'
        }.freeze

        # @param network [Symbol] :main, :mainnet, :test, :testnet, or :stn
        # @param api_key [String, nil] optional WoC API key; sent as a raw
        #   Authorization header value (not Bearer-prefixed)
        # @param http_client [#request, nil] injectable HTTP client for testing
        def initialize(network: :main, api_key: nil, http_client: nil)
          super()
          NETWORKS.fetch(network) { raise ArgumentError, "unknown network: #{network}" }
          wrapped_client = api_key ? RawAuthClient.new(api_key, http_client) : http_client
          @protocol = BSV::Network::Protocols::WoCREST.new(
            network: network,
            api_key: nil,
            http_client: wrapped_client
          )
        end

        # Verify that a merkle root is valid for the given block height.
        #
        # @param root [String] merkle root as a hex string
        # @param height [Integer] block height
        # @return [Boolean]
        # @raise [BSV::Network::ChainProviderError] on network or API error
        def valid_root_for_height?(root, height)
          result = @protocol.call(:valid_root, root, height)
          return false if result.not_found?

          if result.error?
            raise BSV::Network::ChainProviderError.new(
              result.message.to_s,
              status_code: result.metadata[:status_code]
            )
          end

          result.data == true
        end

        # Return the current blockchain height.
        #
        # @return [Integer]
        # @raise [BSV::Network::ChainProviderError] on network or API error
        def current_height
          result = @protocol.call(:current_height)
          return result.data if result.success?

          raise BSV::Network::ChainProviderError.new(
            result.message.to_s,
            status_code: result.metadata[:status_code]
          )
        end

        # Wraps an injectable HTTP client to set a raw Authorization header value
        # before forwarding the request. This preserves the WoC convention of
        # sending the API key without a Bearer prefix.
        class RawAuthClient
          def initialize(api_key, inner_client)
            @api_key = api_key
            @inner_client = inner_client
          end

          def request(uri, req)
            req['Authorization'] = @api_key
            if @inner_client
              @inner_client.request(uri, req)
            else
              Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
                http.request(req)
              end
            end
          end
        end
      end
    end
  end
end
