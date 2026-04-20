# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module BSV
  module Wallet
    module Substrates
      # BRC-100 wallet substrate that delegates all Interface methods to a remote
      # wallet server via JSON-over-HTTP (POST #{base_url}/#{camelCaseMethodName}).
      #
      # Key conversion is handled by {BSV::WireFormat}: Ruby snake_case symbol keys
      # in args are converted to camelCase strings before the request, and the
      # camelCase JSON response is converted back to snake_case symbol keys.
      #
      # @example
      #   wallet = BSV::Wallet::Substrates::HTTPWalletJSON.new('http://localhost:3321',
      #                                                         originator: 'myapp.example.com')
      #   result = wallet.get_public_key({ identity_key: true })
      #   # => { public_key: '02abc...' }
      class HTTPWalletJSON
        include BSV::Wallet::BRC100::Interface

        # Maps the 28 BRC-100 Interface method symbols to their camelCase HTTP endpoint names.
        # Derived from Wire::Serializer::CALL_CODES keys via BSV::WireFormat.snake_to_camel.
        METHOD_NAMES = BSV::Wallet::Wire::Serializer::CALL_CODES.keys.to_h do |sym|
          [sym, BSV::WireFormat.snake_to_camel(sym.to_s)]
        end.freeze

        # @param base_url [String] base URL of the remote wallet server (e.g. 'http://localhost:3321')
        # @param originator [String, nil] FQDN of the originating application (sent as Origin/Originator headers)
        # @param http_client [Object, nil] injectable HTTP client for testing; must respond to
        #   `start(uri, &block)` returning a Net::HTTP-compatible response
        def initialize(base_url, originator: nil, http_client: nil)
          @base_url = base_url
          @originator = originator
          @http_client = http_client
        end

        # Per-call originator is accepted for Interface conformance but not forwarded.
        # The Origin header uses the constructor-level @originator for the lifetime of
        # the connection — matching the TS SDK's HTTPWalletJSON, which also ignores per-call
        # originator. WalletWireTransceiver supports per-call originator because the wire
        # frame encodes it per-message; HTTP substrates identify by connection, not by call.
        # rubocop:disable Lint/UnusedMethodArgument

        def create_action(args, originator: nil)
          call(METHOD_NAMES[:create_action], args)
        end

        def sign_action(args, originator: nil)
          call(METHOD_NAMES[:sign_action], args)
        end

        def abort_action(args, originator: nil)
          call(METHOD_NAMES[:abort_action], args)
        end

        def list_actions(args, originator: nil)
          call(METHOD_NAMES[:list_actions], args)
        end

        def internalize_action(args, originator: nil)
          call(METHOD_NAMES[:internalize_action], args)
        end

        def list_outputs(args, originator: nil)
          call(METHOD_NAMES[:list_outputs], args)
        end

        def relinquish_output(args, originator: nil)
          call(METHOD_NAMES[:relinquish_output], args)
        end

        def get_public_key(args, originator: nil)
          call(METHOD_NAMES[:get_public_key], args)
        end

        def reveal_counterparty_key_linkage(args, originator: nil)
          call(METHOD_NAMES[:reveal_counterparty_key_linkage], args)
        end

        def reveal_specific_key_linkage(args, originator: nil)
          call(METHOD_NAMES[:reveal_specific_key_linkage], args)
        end

        def encrypt(args, originator: nil)
          call(METHOD_NAMES[:encrypt], args)
        end

        def decrypt(args, originator: nil)
          call(METHOD_NAMES[:decrypt], args)
        end

        def create_hmac(args, originator: nil)
          call(METHOD_NAMES[:create_hmac], args)
        end

        def verify_hmac(args, originator: nil)
          call(METHOD_NAMES[:verify_hmac], args)
        end

        def create_signature(args, originator: nil)
          call(METHOD_NAMES[:create_signature], args)
        end

        def verify_signature(args, originator: nil)
          call(METHOD_NAMES[:verify_signature], args)
        end

        def acquire_certificate(args, originator: nil)
          call(METHOD_NAMES[:acquire_certificate], args)
        end

        def list_certificates(args, originator: nil)
          call(METHOD_NAMES[:list_certificates], args)
        end

        def prove_certificate(args, originator: nil)
          call(METHOD_NAMES[:prove_certificate], args)
        end

        def relinquish_certificate(args, originator: nil)
          call(METHOD_NAMES[:relinquish_certificate], args)
        end

        def discover_by_identity_key(args, originator: nil)
          call(METHOD_NAMES[:discover_by_identity_key], args)
        end

        def discover_by_attributes(args, originator: nil)
          call(METHOD_NAMES[:discover_by_attributes], args)
        end

        def is_authenticated(args = {}, originator: nil)
          call(METHOD_NAMES[:is_authenticated], args)
        end

        def wait_for_authentication(args = {}, originator: nil)
          call(METHOD_NAMES[:wait_for_authentication], args)
        end

        def get_height(args = {}, originator: nil)
          call(METHOD_NAMES[:get_height], args)
        end

        def get_header_for_height(args, originator: nil)
          call(METHOD_NAMES[:get_header_for_height], args)
        end

        def get_network(args = {}, originator: nil)
          call(METHOD_NAMES[:get_network], args)
        end

        def get_version(args = {}, originator: nil)
          call(METHOD_NAMES[:get_version], args)
        end

        # rubocop:enable Lint/UnusedMethodArgument

        private

        # Posts args to the remote wallet endpoint for the given camelCase method name.
        #
        # Outbound: converts snake_case symbol keys to camelCase strings via WireFormat.to_wire.
        # Inbound:  converts camelCase string keys to snake_case symbols via WireFormat.from_wire.
        # Errors:   non-2xx response raises the appropriate WalletError subclass.
        #
        # @param method_name [String] camelCase endpoint name (e.g. 'getPublicKey')
        # @param args [Hash] method arguments (snake_case symbol keys)
        # @return [Hash] response with snake_case symbol keys
        def call(method_name, args)
          args ||= {}
          wire_args = BSV::WireFormat.to_wire(args)
          body = JSON.generate(wire_args)

          uri = build_uri(method_name)
          headers = build_headers

          response = execute_request(uri, body, headers)

          handle_response(response, method_name, args)
        end

        def build_uri(method_name)
          URI.parse("#{@base_url}/#{method_name}")
        end

        def build_headers
          h = {
            'Content-Type' => 'application/json',
            'Accept' => 'application/json'
          }

          if @originator
            origin_value = to_origin_header(@originator)
            h['Origin']      = origin_value
            h['Originator']  = origin_value
          end

          h
        end

        # Converts an originator domain to a full Origin header value.
        # Prepends 'http://' if no scheme is present (matching TS SDK toOriginHeader).
        def to_origin_header(originator)
          return originator if originator.match?(%r{\A[a-z][a-z0-9+.-]*://}i)

          "http://#{originator}"
        end

        def execute_request(uri, body, headers)
          if @http_client
            @http_client.post(uri, body, headers)
          else
            Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
              request = Net::HTTP::Post.new(uri.request_uri, headers)
              request.body = body
              http.request(request)
            end
          end
        end

        def handle_response(response, method_name, args)
          code = response.code.to_i

          unless (200..299).cover?(code)
            data = begin
              parse_json_body(response.body)
            rescue JSON::ParserError
              nil
            end
            raise_error_response(code, data, method_name, args)
          end

          data = parse_json_body(response.body)
          return {} if data.nil?

          data.is_a?(Hash) ? BSV::WireFormat.from_wire(data) : data
        end

        def parse_json_body(body)
          return nil if body.nil? || body.empty?

          JSON.parse(body)
        end

        def raise_error_response(code, data, method_name, _args)
          if code == 400 && data.is_a?(Hash) && data['isError']
            case data['code']
            when 5
              raise BSV::Wallet::WalletError.new(data['message'] || 'Review actions required', 5)
            when 6
              raise BSV::Wallet::InvalidParameterError, data['parameter'] || 'unknown'
            when 7
              raise BSV::Wallet::InsufficientFundsError, data['message']
            end
          end

          message = (data.is_a?(Hash) && data['message']) ||
                    "HTTP #{code} error calling #{method_name}"
          raise BSV::Wallet::WalletError, message
        end
      end
    end
  end
end
