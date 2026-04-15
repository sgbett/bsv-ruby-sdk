# frozen_string_literal: true

require 'base64'
require 'json'
require 'timeout'

module BSV
  module Auth
    # Rack middleware providing BRC-104 server-side authentication.
    #
    # Intercepts three categories of request:
    #
    # 1. +POST /.well-known/auth+ — BRC-31 handshake (initialRequest, certificateRequest, etc.).
    #    Delegates to an internal {Peer} instance via {BridgeTransport}.
    #
    # 2. Requests carrying +x-bsv-auth-*+ headers — general authenticated messages.
    #    Verifies the signature, calls the downstream app, and signs the response.
    #
    # 3. Everything else — passed through to the downstream app unchanged.
    #
    # @example Mounting in a Rack application
    #   use BSV::Auth::AuthMiddleware, wallet: my_wallet
    class AuthMiddleware
      # Rack env key for the request input IO.
      RACK_INPUT = 'rack.input'

      # Rack env key for the HTTP method.
      REQUEST_METHOD = 'REQUEST_METHOD'

      # Rack env key for the URL path.
      PATH_INFO = 'PATH_INFO'

      # Rack env key for the query string.
      QUERY_STRING = 'QUERY_STRING'

      # Well-known path for BRC-31 handshake messages.
      AUTH_ENDPOINT = '/.well-known/auth'

      # Rack env prefix for HTTP headers.
      HTTP_PREFIX = 'HTTP_'

      # @param app [#call] downstream Rack application
      # @param wallet [BSV::Wallet::Interface] server wallet for signing and verification
      # @param session_manager [SessionManager, nil] optional; defaults to a new SessionManager
      # @param certificates_to_request [Hash, nil] optional certificate requirements
      def initialize(app, wallet:, session_manager: nil, certificates_to_request: nil)
        @app             = app
        @wallet          = wallet
        @session_manager = session_manager || SessionManager.new

        @bridge    = BridgeTransport.new
        @peer      = Peer.new(
          wallet: wallet,
          transport: @bridge,
          session_manager: @session_manager,
          certificates_to_request: certificates_to_request
        )
      end

      # Processes a Rack request.
      #
      # @param env [Hash] Rack environment
      # @return [Array] Rack response triplet [status, headers, body]
      def call(env)
        if well_known_auth_request?(env)
          handle_auth_endpoint(env)
        elsif auth_headers?(env)
          handle_authenticated_request(env)
        else
          @app.call(env)
        end
      end

      private

      # Handles a POST /.well-known/auth request (handshake).
      #
      # Reads the JSON body, converts keys to snake_case symbols, injects the
      # message into the internal Peer, and returns the response as camelCase JSON.
      def handle_auth_endpoint(env)
        body_str = read_body(env)
        return json_error(400, 'Empty body') if body_str.nil? || body_str.empty?

        raw = JSON.parse(body_str)
        message = snake_case_keys(raw)

        @bridge.inject(message)
        response_message = @bridge.wait_for_response

        camel = camel_case_keys(response_message)
        [200, { 'content-type' => 'application/json' }, [JSON.generate(camel)]]
      rescue JSON::ParserError => e
        json_error(400, "Invalid JSON: #{e.message}")
      rescue AuthError => e
        json_error(401, e.message)
      rescue Timeout::Error
        json_error(504, 'Auth handshake timed out')
      end

      # Handles a request with x-bsv-auth-* headers (general authenticated message).
      #
      # Verifies the request signature via Peer, calls the downstream app, and
      # signs the response with BRC-104 response headers.
      def handle_authenticated_request(env)
        auth_headers = extract_rack_auth_headers(env)

        # Validate required headers are present
        required = %w[version identity_key nonce your_nonce signature request_id]
        missing = required.reject { |k| auth_headers[k] }
        return [401, { 'content-type' => 'text/plain' }, ['Unauthorized']] if missing.any?

        body_bytes = read_body(env) || ''

        request_id_b64  = auth_headers['request_id']
        request_id_bin  = ::Base64.strict_decode64(request_id_b64)

        # Build signed headers from the request (non-auth x-bsv-* and content-type, etc.)
        request_headers_for_signing = collect_request_headers_for_signing(env)

        payload_bin = AuthPayload.serialize_request(
          request_nonce: request_id_bin,
          method: env[REQUEST_METHOD],
          path: env[PATH_INFO],
          query: env[QUERY_STRING].to_s.empty? ? nil : env[QUERY_STRING],
          headers: request_headers_for_signing,
          body: body_bytes.empty? ? nil : body_bytes
        )

        identity_key = auth_headers['identity_key']
        msg_nonce    = auth_headers['nonce']
        your_nonce   = auth_headers['your_nonce']
        sig_hex      = auth_headers['signature']
        sig_bytes    = [sig_hex].pack('H*').bytes

        auth_message = {
          version: auth_headers['version'],
          message_type: 'general',
          identity_key: identity_key,
          nonce: msg_nonce,
          your_nonce: your_nonce,
          signature: sig_bytes,
          payload: payload_bin.bytes
        }

        begin
          @bridge.inject(auth_message)
          # Wait for Peer to process — Peer fires no response for general messages
          # but may raise AuthError if signature verification fails.
          # The bridge may not receive a queued response; we just need to know it
          # succeeded without an error.
          @bridge.drain_if_pending
        rescue ArgumentError
          # DER parsing or other signature-related ArgumentErrors from the
          # crypto layer should be treated as auth failures, not programming errors.
          return [401, { 'content-type' => 'text/plain' }, ['Unauthorized']]
        end

        # Rewind body so downstream app can read it
        rewind_body(env)

        downstream_status, downstream_headers, downstream_body = @app.call(env)

        body_str = collect_body(downstream_body)

        # Build response payload for signing
        response_headers_for_signing = AuthHeaders.filter_response_headers(downstream_headers)

        response_payload_bin = AuthPayload.serialize_response(
          request_id: request_id_bin,
          status: downstream_status,
          headers: response_headers_for_signing,
          body: body_str.empty? ? nil : body_str
        )

        # Look up the session using your_nonce (that is our session nonce)
        session = @session_manager.get_session(your_nonce)
        return [401, { 'content-type' => 'text/plain' }, ['Unauthorized']] unless session

        # Generate a fresh response nonce
        response_nonce = ::Base64.strict_encode64(::SecureRandom.random_bytes(32))
        key_id         = "#{response_nonce} #{session.peer_nonce}"

        sig_result = @wallet.create_signature({
                                                data: response_payload_bin.bytes,
                                                protocol_id: Peer::AUTH_PROTOCOL,
                                                key_id: key_id,
                                                counterparty: identity_key
                                              })

        our_identity_key = @peer.identity_key
        sig_hex_out      = sig_result[:signature].pack('C*').unpack1('H*')

        auth_response_headers = {
          AuthHeaders::VERSION => BSV::Auth::AUTH_VERSION,
          AuthHeaders::IDENTITY_KEY => our_identity_key,
          AuthHeaders::NONCE => response_nonce,
          AuthHeaders::YOUR_NONCE => session.peer_nonce,
          AuthHeaders::SIGNATURE => sig_hex_out,
          AuthHeaders::REQUEST_ID => request_id_b64
        }

        merged_headers = downstream_headers.merge(auth_response_headers)
        [downstream_status, merged_headers, [body_str]]
      rescue AuthError
        [401, { 'content-type' => 'text/plain' }, ['Unauthorized']]
      end

      # Returns true when the request is POST /.well-known/auth.
      def well_known_auth_request?(env)
        env[REQUEST_METHOD] == 'POST' && env[PATH_INFO] == AUTH_ENDPOINT
      end

      # Returns true when the request carries x-bsv-auth-version header.
      def auth_headers?(env)
        env.key?('HTTP_X_BSV_AUTH_VERSION')
      end

      # Reads the full body from rack.input without consuming it.
      # Rewinds after reading so downstream middleware can re-read.
      def read_body(env)
        input = env[RACK_INPUT]
        return nil unless input

        body = input.read
        input.rewind
        body
      end

      # Rewinds rack.input so the downstream app can read the body.
      def rewind_body(env)
        env[RACK_INPUT]&.rewind
      end

      # Joins a Rack body (array or each-able) into a single string.
      def collect_body(body)
        return '' if body.nil?

        body.to_a.join
      end

      # Extracts x-bsv-auth-* headers from the Rack env.
      #
      # Rack uppercases headers and prefixes with HTTP_, replacing hyphens with
      # underscores. For example, +x-bsv-auth-nonce+ becomes +HTTP_X_BSV_AUTH_NONCE+.
      # We normalise back to lowercase without the HTTP_ prefix.
      #
      # Returns a plain Hash with lowercased short keys (e.g. 'nonce', 'identity_key').
      def extract_rack_auth_headers(env)
        result = {}
        prefix = 'HTTP_X_BSV_AUTH_'
        env.each do |key, value|
          next unless key.start_with?(prefix)

          short_key = key[prefix.length..].downcase
          result[short_key] = value
        end
        result
      end

      # Collects headers to be signed from the Rack request env.
      #
      # Extracts content-type and x-bsv-* (non-auth) headers, converts from Rack
      # env format back to HTTP header format, and passes through filter_request_headers.
      def collect_request_headers_for_signing(env)
        headers = {}
        env.each do |key, value|
          next unless key.start_with?(HTTP_PREFIX)

          header_name = key[HTTP_PREFIX.length..].downcase.tr('_', '-')
          next unless header_name == 'content-type' ||
                      (header_name.start_with?('x-bsv-') && !header_name.start_with?('x-bsv-auth'))

          headers[header_name] = value
        end

        return [] if headers.empty?

        AuthHeaders.filter_request_headers(headers)
      end

      # Converts a Hash with string camelCase keys to snake_case symbol keys (shallow).
      def snake_case_keys(hash)
        hash.transform_keys { |k| camel_to_snake(k.to_s).to_sym }
      end

      # Converts a Hash with snake_case symbol/string keys to camelCase string keys (shallow).
      def camel_case_keys(hash)
        hash.transform_keys { |k| snake_to_camel(k.to_s) }
      end

      # Converts camelCase string to snake_case.
      def camel_to_snake(str)
        str.gsub(/([A-Z])/) { "_#{::Regexp.last_match(1).downcase}" }.sub(/^_/, '')
      end

      # Converts snake_case string to camelCase.
      def snake_to_camel(str)
        parts = str.split('_')
        return str if parts.empty?

        parts[0] + parts[1..].map(&:capitalize).join
      end

      # Returns a simple JSON error response.
      def json_error(status, message)
        body = JSON.generate({ error: message })
        [status, { 'content-type' => 'application/json' }, [body]]
      end

      # BridgeTransport — internal transport bridging HTTP ↔ Peer.
      #
      # The middleware injects incoming messages via {#inject} and reads the
      # Peer's response via {#wait_for_response}. When the Peer processes a
      # general message it calls back into {#send}, but general message handling
      # produces no protocol response — {#drain_if_pending} consumes any queued
      # value without blocking.
      class BridgeTransport
        include BSV::Auth::Transport

        DEFAULT_TIMEOUT = 30

        def initialize
          @on_data_callback = nil
          @response_queue   = Queue.new
        end

        # Called by Peer to send a response back to the HTTP client.
        def send(message)
          @response_queue.push(message)
        end

        # Registers the Peer's incoming-message callback.
        def on_data(&block)
          @on_data_callback = block
        end

        # Delivers an incoming message to the Peer.
        def inject(message)
          @on_data_callback&.call(message)
        end

        # Blocks until the Peer pushes a response, then returns it.
        def wait_for_response(timeout: DEFAULT_TIMEOUT)
          Timeout.timeout(timeout) { @response_queue.pop }
        end

        # Consumes a queued response if one is present, without blocking.
        # Used after general message processing (Peer fires no protocol response).
        def drain_if_pending
          @response_queue.pop(true)
        rescue ThreadError
          # Queue was empty — nothing to drain
        end
      end

      private_constant :BridgeTransport
    end
  end
end
