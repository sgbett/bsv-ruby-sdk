# frozen_string_literal: true

require 'json'

module BSV
  module X402
    # Immutable value object representing an x402 payment challenge (spec §4).
    #
    # A challenge is issued by a server as an HTTP 402 response header
    # (+X402-Challenge+). The client reads it, constructs a payment transaction,
    # and returns the proof in the follow-up request.
    #
    # Construction validates all required fields. Use +Challenge.from_header+ or
    # +Challenge.from_json+ for deserialisation; use +#to_header+ / +#to_json+
    # for serialisation.
    #
    # The +scheme+ field is validated against +bsv-tx-v1+ for production use.
    # The test-vector conformance suite passes +scheme: 'x402-bsv'+ explicitly
    # and uses the +skip_scheme_validation: true+ escape hatch.
    class Challenge
      # Normative scheme identifier for BSV x402 v1.0.
      SCHEME = 'bsv-tx-v1'

      # Protocol version supported by this implementation.
      SUPPORTED_VERSION = 1

      # @return [Integer] protocol version (must be 1)
      attr_reader :v

      # @return [String] scheme identifier
      attr_reader :scheme

      # @return [String] domain the challenge was issued for
      attr_reader :domain

      # @return [String] HTTP method bound to this challenge
      attr_reader :method

      # @return [String] URL path bound to this challenge
      attr_reader :path

      # @return [String] URL query string bound to this challenge
      attr_reader :query

      # @return [String] SHA-256 hex digest of the bound request headers
      attr_reader :req_headers_sha256

      # @return [String] SHA-256 hex digest of the bound request body
      attr_reader :req_body_sha256

      # @return [Integer] required payment amount in satoshis
      attr_reader :amount_sats

      # @return [String] hex-encoded locking script for the payment output
      attr_reader :payee_locking_script_hex

      # @return [BSV::X402::NonceUTXO] nonce UTXO that must be spent in the payment
      attr_reader :nonce_utxo

      # @return [Integer] Unix timestamp at which the challenge expires
      attr_reader :expires_at

      # @return [Boolean] whether the server requires mempool acceptance before responding
      attr_reader :require_mempool_accept

      def initialize(
        v:, scheme:, domain:, method:, path:, query:,
        req_headers_sha256:, req_body_sha256:,
        amount_sats:, payee_locking_script_hex:,
        nonce_utxo:, expires_at:, require_mempool_accept:,
        skip_scheme_validation: false
      )
        @v = v
        @scheme                   = scheme
        @domain                   = domain
        @method                   = method
        @path                     = path
        @query                    = query
        @req_headers_sha256       = req_headers_sha256
        @req_body_sha256          = req_body_sha256
        @amount_sats              = amount_sats
        @payee_locking_script_hex = payee_locking_script_hex
        @nonce_utxo               = nonce_utxo
        @expires_at               = expires_at
        @require_mempool_accept   = require_mempool_accept

        validate!(skip_scheme_validation: skip_scheme_validation)
        freeze
      end

      # Parses a +Challenge+ from a JSON string.
      #
      # @param json_string [String]
      # @param skip_scheme_validation [Boolean] bypass scheme check (test vectors only)
      # @return [Challenge]
      # @raise [BSV::X402::EncodingError] if the JSON is malformed
      # @raise [BSV::X402::ValidationError] if required fields are missing or invalid
      def self.from_json(json_string, skip_scheme_validation: false)
        hash = JSON.parse(json_string)
        from_hash(hash, skip_scheme_validation: skip_scheme_validation)
      rescue JSON::ParserError => e
        raise EncodingError, "invalid JSON in challenge: #{e.message}"
      end

      # Decodes a +Challenge+ from a base64url-encoded header value.
      #
      # @param base64url_string [String] value of the +X402-Challenge+ header
      # @param skip_scheme_validation [Boolean] bypass scheme check (test vectors only)
      # @return [Challenge]
      # @raise [BSV::X402::EncodingError] if decoding or JSON parsing fails
      # @raise [BSV::X402::ValidationError] if required fields are missing or invalid
      def self.from_header(base64url_string, skip_scheme_validation: false)
        json_bytes = Encoding.base64url_decode(base64url_string)
        from_json(json_bytes, skip_scheme_validation: skip_scheme_validation)
      end

      # Returns the canonical JSON representation (RFC 8785) of this challenge.
      #
      # @return [String]
      def to_json(*_args)
        CanonicalJSON.encode(to_hash)
      end

      # Returns the base64url encoding of the canonical JSON, suitable for use
      # as the +X402-Challenge+ HTTP header value.
      #
      # @return [String]
      def to_header
        Encoding.base64url_encode(to_json)
      end

      # Returns the SHA-256 hex digest of the canonical JSON bytes.
      # This is the value the client stores in +proof.challenge_sha256+.
      #
      # @return [String] lowercase hex string
      def sha256
        BSV::Primitives::Digest.sha256(to_json).unpack1('H*')
      end

      # Returns +true+ if the challenge has expired.
      #
      # @param now [Integer] current Unix timestamp (defaults to +Time.now.to_i+)
      # @return [Boolean]
      def expired?(now = Time.now.to_i)
        now > expires_at
      end

      # Returns a plain hash with string keys, matching the canonical field order.
      #
      # @return [Hash]
      def to_hash
        {
          'amount_sats' => amount_sats,
          'domain' => domain,
          'expires_at' => expires_at,
          'method' => method,
          'nonce_utxo' => nonce_utxo.to_hash,
          'path' => path,
          'payee_locking_script_hex' => payee_locking_script_hex,
          'query' => query,
          'req_body_sha256' => req_body_sha256,
          'req_headers_sha256' => req_headers_sha256,
          'require_mempool_accept' => require_mempool_accept,
          'scheme' => scheme,
          'v' => v
        }
      end

      private

      def validate!(skip_scheme_validation: false)
        required_string_fields.each do |field|
          value = send(field)
          raise ValidationError, "challenge missing required field: #{field}" if value.nil? || value.to_s.empty?
        end

        raise ValidationError, "challenge.v must be #{SUPPORTED_VERSION}" unless v == SUPPORTED_VERSION
        raise ValidationError, "challenge.scheme must be '#{SCHEME}'" unless skip_scheme_validation || scheme == SCHEME
        raise ValidationError, 'challenge.amount_sats must be a positive integer' unless amount_sats.is_a?(Integer) && amount_sats.positive?
        raise ValidationError, 'challenge.expires_at must be an integer' unless expires_at.is_a?(Integer)
        raise ValidationError, 'challenge.nonce_utxo must be a NonceUTXO' unless nonce_utxo.is_a?(NonceUTXO)
      end

      def required_string_fields
        %i[scheme domain method path req_headers_sha256 req_body_sha256 payee_locking_script_hex]
      end

      def self.from_hash(hash, skip_scheme_validation: false)
        nonce_hash = fetch(hash, 'nonce_utxo')
        raise ValidationError, 'challenge missing required field: nonce_utxo' unless nonce_hash.is_a?(Hash)

        new(
          v: fetch(hash, 'v'),
          scheme: fetch(hash, 'scheme'),
          domain: fetch(hash, 'domain'),
          method: fetch(hash, 'method'),
          path: fetch(hash, 'path'),
          query: fetch(hash, 'query'),
          req_headers_sha256: fetch(hash, 'req_headers_sha256'),
          req_body_sha256: fetch(hash, 'req_body_sha256'),
          amount_sats: fetch(hash, 'amount_sats'),
          payee_locking_script_hex: fetch(hash, 'payee_locking_script_hex'),
          nonce_utxo: NonceUTXO.from_hash(nonce_hash),
          expires_at: fetch(hash, 'expires_at'),
          require_mempool_accept: fetch(hash, 'require_mempool_accept'),
          skip_scheme_validation: skip_scheme_validation
        )
      end
      private_class_method :from_hash

      def self.fetch(hash, key)
        return hash[key] if hash.key?(key)
        return hash[key.to_sym] if hash.key?(key.to_sym)

        raise ValidationError, "challenge missing required field: #{key}"
      end
      private_class_method :fetch
    end
  end
end
