# frozen_string_literal: true

require 'net/http'
require 'uri'

module BSV
  module Wallet
    module Substrates
      # Concrete {WalletWire} implementation over HTTP/HTTPS.
      #
      # Transmits binary BRC-103 request frames via HTTP POST to `{base_url}/wallet`
      # using `Content-Type: application/octet-stream`, and returns the raw binary
      # response body.
      #
      # The optional `http_client:` parameter accepts any object responding to
      # `#request(uri, net_http_request)` — matching the injectable client
      # convention used throughout this SDK. When omitted, `Net::HTTP` is used
      # directly.
      #
      # @example Direct wire usage
      #   wire   = BSV::Wallet::Substrates::HTTPWalletWire.new(base_url: 'https://wallet.example')
      #   client = BSV::Wallet::WalletWireTransceiver.new(wire)
      #   client.get_network  #=> { network: :mainnet }
      #
      # @example Convenience factory
      #   client = BSV::Wallet::Substrates::HTTPWalletWire.client(base_url: 'https://wallet.example')
      #   client.get_network  #=> { network: :mainnet }
      class HTTPWalletWire
        include WalletWire

        # @param base_url [String] wallet base URL (e.g. 'https://wallet.example')
        # @param http_client [#request, nil] injectable HTTP client for testing;
        #   must respond to +#request(uri, net_http_request)+. Defaults to +Net::HTTP+.
        # @param headers [Hash] additional headers merged into every request
        def initialize(base_url:, http_client: nil, headers: {})
          @uri         = build_uri(base_url)
          @http_client = http_client
          @headers     = headers.transform_keys(&:to_s)
        end

        # Convenience factory: wraps a new {HTTPWalletWire} in a {WalletWireTransceiver}.
        #
        # @param base_url [String]
        # @param http_client [#request, nil]
        # @param headers [Hash]
        # @return [WalletWireTransceiver]
        def self.client(base_url:, http_client: nil, headers: {})
          WalletWireTransceiver.new(new(base_url: base_url, http_client: http_client, headers: headers))
        end

        # POST binary frame to `{base_url}/wallet` and return the binary response body.
        #
        # @param message [String] binary request frame (ASCII-8BIT)
        # @return [String] binary result frame (ASCII-8BIT)
        # @raise [BSV::Wallet::Error] on non-2xx HTTP status or network failure
        def transmit_to_wallet(message)
          http_post(message)
        rescue BSV::Wallet::Error
          raise
        rescue SocketError, Errno::ECONNREFUSED, Errno::ETIMEDOUT,
               Net::OpenTimeout, Net::ReadTimeout, Net::HTTPError => e
          raise BSV::Wallet::Error.new("wallet connection failed: #{e.message}", code: 1)
        rescue StandardError => e
          raise BSV::Wallet::Error.new("wallet request failed: #{e.message}", code: 1)
        end

        private

        def build_uri(base_url)
          normalised = base_url.to_s.chomp('/')
          URI.parse("#{normalised}/wallet")
        end

        def http_post(body)
          request = Net::HTTP::Post.new(@uri.path)
          @headers.each { |k, v| request[k] = v }
          request['Content-Type'] = 'application/octet-stream'
          request.body = body.respond_to?(:b) ? body.b : body.pack('C*')

          response = execute_request(request)

          raise BSV::Wallet::Error.new("HTTP #{response.code}: #{response.body.to_s.strip}", code: 1) unless response.is_a?(Net::HTTPSuccess)

          (response.body || '').b
        end

        def execute_request(request)
          if @http_client
            @http_client.request(@uri, request)
          else
            Net::HTTP.start(@uri.host, @uri.port, use_ssl: @uri.scheme == 'https') do |http|
              http.request(request)
            end
          end
        end
      end
    end
  end
end
