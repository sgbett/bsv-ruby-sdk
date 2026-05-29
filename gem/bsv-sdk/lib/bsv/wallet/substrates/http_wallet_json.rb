# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module BSV
  module Wallet
    module Substrates
      # JSON-RPC-style HTTP substrate implementing BRC-100.
      #
      # Dispatches all 28 BRC-100 methods as JSON POST requests to
      # {base_url}/v1/wallet/{methodNameInCamelCase}. Request bodies are
      # deep-converted from snake_case to camelCase via {BSV::WireFormat.to_wire};
      # responses are deep-converted back via {BSV::WireFormat.from_wire}.
      #
      # This substrate does NOT use the BRC-103 binary frame codec — it speaks
      # plain JSON over HTTP, matching the Go SDK HTTPWalletJSON implementation.
      #
      # @example
      #   client = BSV::Wallet::Substrates::HTTPWalletJSON.new(
      #     base_url: 'https://wallet.example.com',
      #     headers: { 'Authorization' => 'Bearer token' }
      #   )
      #   client.get_network  # => { network: 'mainnet' }
      class HTTPWalletJSON
        include Interface::BRC100

        # Maps each BRC-100 Ruby method name to its camelCase wire name.
        # authenticated? maps to isAuthenticated — the BRC-100 wire name uses the
        # is_ prefix convention; the Ruby predicate suffix is dropped for the lookup.
        WIRE_METHOD_NAMES = Wire::Calls::CALL_TO_METHOD.each_with_object({}) do |(call_byte, ruby_method), map|
          snake = call_byte == Wire::Calls::IS_AUTHENTICATED ? 'is_authenticated' : ruby_method.to_s
          map[ruby_method] = BSV::WireFormat.snake_to_camel(snake)
        end.freeze

        # @param base_url [String] wallet base URL (e.g. 'https://wallet.example')
        # @param http_client [#request, nil] injectable HTTP client for testing;
        #   must respond to +#request(uri, net_http_request)+. Defaults to +Net::HTTP+.
        # @param headers [Hash] additional headers merged into every request
        def initialize(base_url:, http_client: nil, headers: {})
          @base_url    = base_url.to_s.chomp('/')
          @http_client = http_client
          @headers     = headers.transform_keys(&:to_s)
        end

        Wire::Calls::CALL_TO_METHOD.each_value do |method_name|
          define_method(method_name) do |**args|
            _dispatch(method_name, args)
          end
        end

        private

        def _dispatch(method_name, args)
          wire_name = WIRE_METHOD_NAMES.fetch(method_name)
          url       = URI.parse("#{@base_url}/v1/wallet/#{wire_name}")
          body      = args.empty? ? {} : BSV::WireFormat.to_wire(args)

          response = _post(url, body)
          _handle_response(response)
        end

        def _post(url, body)
          req = Net::HTTP::Post.new(url)
          @headers.each { |k, v| req[k] = v }
          req['Content-Type'] = 'application/json'
          req['Accept']       = 'application/json'
          req.body = body.to_json

          _execute_request(url, req)
        rescue BSV::Wallet::Error
          raise
        rescue StandardError => e
          raise BSV::Wallet::Error.new("HTTP request failed: #{e.message}", code: 1)
        end

        def _execute_request(url, req)
          if @http_client
            @http_client.request(url, req)
          else
            Net::HTTP.start(url.host, url.port,
                            use_ssl: url.scheme == 'https') { |conn| conn.request(req) }
          end
        end

        def _handle_response(response)
          status = response.code.to_i
          raw    = response.body.to_s

          if (200..299).cover?(status)
            _parse_success(raw, status)
          else
            _raise_error(raw)
          end
        end

        def _parse_success(raw, status)
          return {} if status == 204 || raw.empty?

          begin
            parsed = JSON.parse(raw)
          rescue JSON::ParserError => e
            raise BSV::Wallet::Error.new("Invalid JSON in response: #{e.message}", code: 1)
          end

          return parsed unless parsed.is_a?(Hash)

          BSV::WireFormat.from_wire(parsed)
        end

        def _raise_error(raw)
          error_hash = begin
            JSON.parse(raw)
          rescue JSON::ParserError
            {}
          end

          code    = error_hash['code'].to_i
          message = error_hash['message'].to_s
          stack   = error_hash['stack'].to_s
          code    = 1 if code.zero?

          raise BSV::Wallet.error_from_wire(code, message.empty? ? raw : message, stack)
        end
      end
    end
  end
end
