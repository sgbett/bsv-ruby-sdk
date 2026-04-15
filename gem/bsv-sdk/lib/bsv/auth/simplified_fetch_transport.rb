# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'base64'

module BSV
  module Auth
    # BRC-104 client-side HTTP transport implementing {BSV::Auth::Transport}.
    #
    # Maps BRC-103 auth message types to HTTP requests:
    #
    # - Non-general messages (+initialRequest+, +initialResponse+,
    #   +certificateRequest+, +certificateResponse+) are POSTed as JSON to
    #   +#{base_url}/.well-known/auth+. Keys are converted to camelCase on
    #   the wire and back to snake_case symbols on receipt.
    #
    # - General messages have their binary payload deserialised via
    #   {AuthPayload.deserialize_request}, sent as a real HTTP request with
    #   +x-bsv-auth-*+ headers attached, and the HTTP response serialised
    #   back to a binary payload via {AuthPayload.serialize_response}.
    #
    # @example
    #   transport = BSV::Auth::SimplifiedFetchTransport.new('https://api.example.com')
    #   transport.on_data { |msg| peer.handle_incoming_message(msg) }
    #   transport.send(message)
    class SimplifiedFetchTransport
      include BSV::Auth::Transport

      # @param base_url [String] scheme + host (+ optional port), e.g. "https://api.example.com"
      # @param http_client [Class, nil] injectable HTTP client; defaults to Net::HTTP
      def initialize(base_url, http_client: nil)
        @base_url    = base_url.chomp('/')
        @http_client = http_client || Net::HTTP
        @on_data_callback = nil
      end

      # Registers the callback invoked when a response arrives.
      #
      # Must be called before {#send}.
      #
      # @yieldparam message [Hash] incoming auth message with symbol keys
      def on_data(&block)
        @on_data_callback = block
      end

      # Sends an auth message to the remote peer.
      #
      # @param message [Hash] auth message produced by {BSV::Auth::Peer}
      # @raise [RuntimeError] if no callback has been registered via {#on_data}
      def send(message)
        raise "#{self.class}#send called before on_data callback was registered" if @on_data_callback.nil?

        type = fetch_key(message, :message_type)

        if type == MSG_GENERAL
          send_general(message)
        else
          send_non_general(message)
        end
      end

      private

      # -------------------------------------------------------------------------
      # Non-general path: POST JSON to /.well-known/auth
      # -------------------------------------------------------------------------

      def send_non_general(message)
        auth_url  = "#{@base_url}/.well-known/auth"
        body_json = JSON.generate(BSV::WireFormat.to_wire(message))

        uri      = URI.parse(auth_url)
        response = perform_http_request(uri, 'POST', { 'Content-Type' => 'application/json' }, body_json)

        unless http_success?(response)
          body_preview = safe_body_preview(response_body(response))
          raise "HTTP #{response.code} from #{auth_url}: #{body_preview}"
        end

        response_hash = JSON.parse(response_body(response))
        @on_data_callback.call(BSV::WireFormat.from_wire(response_hash))
      end

      # -------------------------------------------------------------------------
      # General message path: reconstruct real HTTP request from binary payload
      # -------------------------------------------------------------------------

      def send_general(message)
        payload = fetch_key(message, :payload)
        decoded = AuthPayload.deserialize_request(array_to_binary(payload))

        request_nonce = decoded[:request_nonce] # raw 32-byte binary
        method        = decoded[:method]
        path          = decoded[:path].to_s
        query         = decoded[:query].to_s
        headers       = headers_array_to_hash(decoded[:headers])
        body          = decoded[:body]

        url = "#{@base_url}#{path}#{query}"
        uri = URI.parse(url)

        # Add x-bsv-auth-* headers
        auth_headers = build_auth_request_headers(message, request_nonce)
        all_headers  = headers.merge(auth_headers)

        response = perform_http_request(uri, method, all_headers, body)

        # Validate required auth headers on the response
        resp_headers = response_headers_hash(response)
        validate_general_response_headers!(url, response, resp_headers)

        # Parse optional requested-certificates header
        requested_certs = parse_requested_certificates_header(url, resp_headers)

        # Serialise the response into a binary payload
        filtered = AuthHeaders.filter_response_headers(resp_headers)
        response_payload = AuthPayload.serialize_response(
          request_id: request_nonce,
          status: response.code.to_i,
          headers: filtered,
          body: response_body(response)
        )

        # Build and deliver the response AuthMessage
        message_type = resp_headers[AuthHeaders::MESSAGE_TYPE] == MSG_CERT_REQUEST ? MSG_CERT_REQUEST : MSG_GENERAL

        response_message = {
          version: resp_headers[AuthHeaders::VERSION],
          message_type: message_type,
          identity_key: resp_headers[AuthHeaders::IDENTITY_KEY],
          nonce: resp_headers[AuthHeaders::NONCE],
          your_nonce: resp_headers[AuthHeaders::YOUR_NONCE],
          requested_certificates: requested_certs,
          payload: binary_to_array(response_payload),
          signature: hex_to_array(resp_headers[AuthHeaders::SIGNATURE].to_s)
        }

        @on_data_callback.call(response_message)
      end

      # -------------------------------------------------------------------------
      # HTTP helpers
      # -------------------------------------------------------------------------

      # Performs an HTTP request using Net::HTTP (or the injected client).
      #
      # The injected client must respond to +.start(host, port, use_ssl:) { |h| ... }+
      # and the yielded object must respond to +.request(req)+.
      def perform_http_request(uri, method, headers, body)
        use_ssl = uri.scheme == 'https'

        request_obj = build_net_http_request(uri, method, headers, body)

        begin
          @http_client.start(uri.host, uri.port, use_ssl: use_ssl) do |http|
            http.request(request_obj)
          end
        rescue StandardError => e
          raise "Network error while sending authenticated request to #{uri}: #{e.message}"
        end
      end

      def build_net_http_request(uri, method, headers, body)
        path = uri.request_uri

        req = case method.upcase
              when 'GET'    then Net::HTTP::Get.new(path)
              when 'POST'   then Net::HTTP::Post.new(path)
              when 'PUT'    then Net::HTTP::Put.new(path)
              when 'PATCH'  then Net::HTTP::Patch.new(path)
              when 'DELETE' then Net::HTTP::Delete.new(path)
              when 'HEAD'   then Net::HTTP::Head.new(path)
              else               raise ArgumentError, "Unsupported HTTP method: #{method}"
              end

        headers.each { |k, v| req[k] = v }
        req.body = body if body && !body.empty?

        req
      end

      # -------------------------------------------------------------------------
      # Auth header builders
      # -------------------------------------------------------------------------

      def build_auth_request_headers(message, request_nonce)
        sig = fetch_key(message, :signature)
        {
          AuthHeaders::VERSION => fetch_key(message, :version).to_s,
          AuthHeaders::IDENTITY_KEY => fetch_key(message, :identity_key).to_s,
          AuthHeaders::NONCE => fetch_key(message, :nonce).to_s,
          AuthHeaders::YOUR_NONCE => fetch_key(message, :your_nonce).to_s,
          AuthHeaders::SIGNATURE => signature_to_hex(sig),
          AuthHeaders::REQUEST_ID => ::Base64.strict_encode64(request_nonce)
        }
      end

      def validate_general_response_headers!(url, response, resp_headers)
        missing = [AuthHeaders::VERSION, AuthHeaders::IDENTITY_KEY, AuthHeaders::SIGNATURE].select do |h|
          resp_headers[h].to_s.strip.empty?
        end
        return if missing.empty?

        body_preview = safe_body_preview(response_body(response))
        raise "Received HTTP #{response.code} from #{url} without valid BSV authentication " \
              "(missing headers: #{missing.join(', ')}) - body preview: #{body_preview}"
      end

      def parse_requested_certificates_header(url, resp_headers)
        raw = resp_headers[AuthHeaders::REQUESTED_CERTIFICATES]
        return nil if raw.nil? || raw.strip.empty?

        begin
          JSON.parse(raw)
        rescue JSON::ParserError => e
          raise "Failed to parse #{AuthHeaders::REQUESTED_CERTIFICATES} returned by #{url}: #{raw}. #{e.message}"
        end
      end

      # -------------------------------------------------------------------------
      # Encoding helpers
      # -------------------------------------------------------------------------

      # Encodes a signature (Array<Integer> or String) to lowercase hex.
      def signature_to_hex(sig)
        if sig.is_a?(Array)
          sig.map { |b| b.to_i.to_s(16).rjust(2, '0') }.join
        else
          sig.to_s
        end
      end

      # Decodes a hex string to an Array<Integer>.
      def hex_to_array(hex_str)
        return [] if hex_str.nil? || hex_str.empty?

        [hex_str].pack('H*').bytes
      end

      # Converts a binary String to Array<Integer>.
      def binary_to_array(bin)
        bin.bytes
      end

      # Converts Array<Integer> or String payload to binary String.
      def array_to_binary(payload)
        return payload if payload.is_a?(String)

        payload.map(&:chr).join.force_encoding('BINARY')
      end

      # Converts the headers Array<[key, value]> to a Hash with downcased string keys.
      def headers_array_to_hash(headers_array)
        (headers_array || []).each_with_object({}) do |(k, v), h|
          h[k.to_s.downcase] = v
        end
      end

      # Returns a flat hash of lowercased response headers.
      def response_headers_hash(response)
        result = {}
        response.each_header { |k, v| result[k.downcase] = v }
        result
      end

      def response_body(response)
        response.body || ''
      end

      def http_success?(response)
        code = response.code.to_i
        code >= 200 && code < 300
      end

      # Returns up to 512 printable characters from a response body for error messages.
      def safe_body_preview(body)
        return '' if body.nil? || body.empty?

        preview = body.encode('UTF-8', 'binary', invalid: :replace, undef: :replace)
        preview.length > 512 ? "#{preview[0, 512]}..." : preview
      end

      # Fetches a key from a hash accepting both symbol and string forms.
      def fetch_key(hash, sym_key)
        hash[sym_key] || hash[sym_key.to_s]
      end
    end
  end
end
