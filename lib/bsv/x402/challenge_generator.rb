# frozen_string_literal: true

require 'openssl'
require 'rack'

module BSV
  module X402
    # Builds a {Challenge} from a Rack request environment and configuration.
    #
    # The generator:
    # 1. Extracts the HTTP method, path, query string from the Rack env.
    # 2. Computes the request-binding hashes for the configured bound headers
    #    and the request body (streaming SHA-256 to avoid buffering large bodies).
    # 3. Calls +config.nonce_provider.reserve_nonce+ to obtain a fresh nonce
    #    UTXO (invariant N-3: the provider is responsible for atomic reservation).
    # 4. Constructs and returns a frozen {Challenge}.
    #
    # The Rack body (+rack.input+) is read, hashed, then rewound so that
    # downstream middleware and the application can still read it.
    module ChallengeGenerator
      # Generates a {Challenge} from a Rack env hash and configuration.
      #
      # @param env    [Hash] Rack environment hash
      # @param config [Configuration] effective configuration (may be per-route merged)
      # @param route_options [Hash] per-route option overrides (e.g. +:amount_sats+)
      # @return [Challenge]
      # @raise [BSV::X402::ValidationError] if configuration is incomplete
      def self.generate(env:, config:, route_options: {})
        request = Rack::Request.new(env)

        http_method = env['REQUEST_METHOD'].to_s
        path        = env['PATH_INFO'].to_s
        query       = (env['QUERY_STRING'] || '').to_s

        headers_hash = compute_headers_hash(env, config.bound_headers)
        body_hash    = compute_body_hash(request)

        nonce_utxo = reserve_nonce(config)
        amount     = route_options.fetch(:amount_sats, config.amount_sats)
        domain     = extract_domain(env)
        expires_at = Time.now.to_i + config.expires_in

        Challenge.new(
          v: Challenge::SUPPORTED_VERSION,
          scheme: Challenge::SCHEME,
          domain: domain,
          method: http_method,
          path: path,
          query: query,
          req_headers_sha256: headers_hash,
          req_body_sha256: body_hash,
          amount_sats: amount,
          payee_locking_script_hex: config.payee_locking_script_hex,
          nonce_utxo: nonce_utxo,
          expires_at: expires_at,
          require_mempool_accept: false
        )
      end

      # ------------------------------------------------------------------
      # Private helpers
      # ------------------------------------------------------------------

      # Extracts the host (domain) from the Rack env.
      #
      # Uses +HTTP_HOST+ if present, falling back to +SERVER_NAME+.
      #
      # @param env [Hash]
      # @return [String]
      def self.extract_domain(env)
        (env['HTTP_HOST'] || env['SERVER_NAME'] || '').to_s
      end
      private_class_method :extract_domain

      # Computes the SHA-256 hex digest of the bound request headers.
      #
      # Only the headers listed in +bound_header_names+ are included.
      # Rack stores HTTP headers as +HTTP_HEADER_NAME+ (uppercase, underscores).
      # We normalise to lowercase hyphenated names before hashing.
      #
      # @param env [Hash] Rack environment
      # @param bound_header_names [Array<String>] header names to bind (e.g. 'content-type')
      # @return [String] lowercase hex SHA-256 digest
      def self.compute_headers_hash(env, bound_header_names)
        selected = {}
        Array(bound_header_names).each do |name|
          rack_key = "HTTP_#{name.upcase.tr('-', '_')}"
          value = env[rack_key]
          selected[name.downcase] = value.to_s if value
        end

        RequestBinding.compute_headers_hash(selected)
      end
      private_class_method :compute_headers_hash

      # Computes the SHA-256 hex digest of the request body.
      #
      # Reads from +rack.input+, hashes the bytes, then rewinds the IO so
      # downstream middleware and the application can still read the body.
      # Handles non-rewindable bodies gracefully by catching the error.
      #
      # @param request [Rack::Request]
      # @return [String] lowercase hex SHA-256 digest
      def self.compute_body_hash(request)
        input = request.env['rack.input']
        return RequestBinding.compute_body_hash(nil) unless input

        digest = OpenSSL::Digest.new('SHA256')
        buf    = String.new
        digest.update(buf) while input.read(16_384, buf) && !buf.empty?

        begin
          input.rewind
        rescue IOError
          # Non-rewindable input (e.g. pipe) — body has been consumed but we
          # cannot restore it. Downstream reads will return empty; this is an
          # acceptable trade-off for streaming bodies in a payment gateway.
        end

        digest.hexdigest
      end
      private_class_method :compute_body_hash

      # Obtains a fresh nonce UTXO from the configured provider.
      #
      # Accepts a +NonceUTXO+ directly (already-constructed value object) or
      # any object responding to +reserve_nonce+ (returns a +NonceUTXO+ or
      # a compatible hash).
      #
      # @param config [Configuration]
      # @return [NonceUTXO]
      # @raise [BSV::X402::ValidationError] if no nonce provider is configured
      def self.reserve_nonce(config)
        provider = config.nonce_provider
        raise ValidationError, 'no nonce_provider configured' unless provider

        result = provider.reserve_nonce
        return result if result.is_a?(NonceUTXO)

        NonceUTXO.from_hash(result)
      end
      private_class_method :reserve_nonce
    end
  end
end
