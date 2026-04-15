# frozen_string_literal: true

require 'net/http'
require 'uri'

module BSV
  module Wallet
    module Substrates
      # Binary wire transport that transmits BRC-100 wallet wire messages over HTTP.
      #
      # Implements the single-method WalletWire interface: given a raw binary frame
      # (as an Array of byte integers), parses the call code, maps it to a URL path,
      # and POSTs the payload to the remote wallet endpoint.
      #
      # @example
      #   wire = BSV::Wallet::Substrates::HTTPWalletWire.new('http://localhost:3301')
      #   response_bytes = wire.transmit_to_wallet(frame_bytes)
      class HTTPWalletWire
        # @param base_url [String] the base URL of the remote wallet (e.g. 'http://localhost:3301')
        # @param originator [String, nil] FQDN of the calling application (sent as Origin header)
        # @param http_client [#call, nil] injectable HTTP client for testing; nil uses Net::HTTP
        def initialize(base_url, originator: nil, http_client: nil)
          @base_url = base_url
          @originator = originator
          @http_client = http_client
        end

        # Transmits a binary wallet wire message to the remote wallet.
        #
        # Parses the call code from byte 0, reads the originator from the header,
        # and POSTs the remaining payload bytes to the appropriate URL path.
        #
        # @param message [Array<Integer>] raw wire frame as array of byte integers
        # @return [Array<Integer>] response body as array of byte integers
        # @raise [ArgumentError] if the message is empty or contains an unknown call code
        # @raise [RuntimeError] if the HTTP response indicates an error (non-2xx)
        def transmit_to_wallet(message)
          raise ArgumentError, 'message must not be empty' if message.nil? || message.empty?

          call_code = message[0]
          call_name = BSV::Wallet::Wire::Serializer::METHODS_BY_CODE[call_code]
          raise ArgumentError, "unknown call code: #{call_code}" if call_name.nil?

          originator_length = message[1] || 0
          originator = message[2, originator_length].pack('C*').force_encoding('UTF-8') if originator_length.positive?

          payload_start = 2 + originator_length
          payload = message[payload_start..] || []

          camel_name = BSV::WireFormat.snake_to_camel(call_name.to_s)
          url = "#{@base_url}/#{camel_name}"

          response_body = post_binary(url, payload, originator || @originator)
          response_body.bytes.to_a
        end

        private

        def post_binary(url, payload_bytes, originator)
          uri = URI.parse(url)
          body = payload_bytes.pack('C*')

          if @http_client
            @http_client.call(uri, body, originator)
          else
            perform_request(uri, body, originator)
          end
        end

        def perform_request(uri, body, originator)
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
            request = Net::HTTP::Post.new(uri.request_uri)
            request['Content-Type'] = 'application/octet-stream'
            request['Origin'] = originator if originator && !originator.empty?
            request.body = body
            response = http.request(request)
            raise "HTTPWalletWire: HTTP #{response.code} from #{uri}" unless response.is_a?(Net::HTTPSuccess)

            response.body || ''
          end
        end
      end
    end
  end
end
