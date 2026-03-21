# frozen_string_literal: true

require 'json'

module BSV
  module X402
    # Immutable value object representing an x402 payment proof (spec §5).
    #
    # A proof is submitted by the client in the +X402-Proof+ header of a
    # follow-up request. It binds the payment transaction to the original
    # challenge and the specific request being made.
    #
    # The nested +request+ sub-object mirrors the request-binding fields
    # from the challenge so the verifier can confirm they have not changed.
    # The nested +payment+ sub-object carries the transaction ID and raw
    # transaction bytes.
    class Proof
      # Normative scheme identifier for BSV x402 v1.0.
      SCHEME = 'bsv-tx-v1'

      # Protocol version supported by this implementation.
      SUPPORTED_VERSION = 1

      # @return [Integer] protocol version (must be 1)
      attr_reader :v

      # @return [String] scheme identifier
      attr_reader :scheme

      # @return [String] SHA-256 hex digest of the canonical challenge JSON
      attr_reader :challenge_sha256

      # @return [Hash] request-binding sub-object
      #   Keys: +method+, +path+, +query+, +req_headers_sha256+, +req_body_sha256+
      attr_reader :request

      # @return [Hash] payment sub-object
      #   Keys: +txid+, +rawtx_b64+
      attr_reader :payment

      def initialize(v:, scheme:, challenge_sha256:, request:, payment:)
        @v                = v
        @scheme           = scheme
        @challenge_sha256 = challenge_sha256
        @request          = request.freeze
        @payment          = payment.freeze

        validate!
        freeze
      end

      # Parses a +Proof+ from a JSON string.
      #
      # @param json_string [String]
      # @return [Proof]
      # @raise [BSV::X402::EncodingError] if the JSON is malformed
      # @raise [BSV::X402::ValidationError] if required fields are missing or invalid
      def self.from_json(json_string)
        hash = JSON.parse(json_string)
        from_hash(hash)
      rescue JSON::ParserError => e
        raise EncodingError, "invalid JSON in proof: #{e.message}"
      end

      # Decodes a +Proof+ from a base64url-encoded header value.
      #
      # @param base64url_string [String] value of the +X402-Proof+ header
      # @return [Proof]
      # @raise [BSV::X402::EncodingError] if decoding or JSON parsing fails
      # @raise [BSV::X402::ValidationError] if required fields are missing or invalid
      def self.from_header(base64url_string)
        json_bytes = Encoding.base64url_decode(base64url_string)
        from_json(json_bytes)
      end

      # Returns the canonical JSON representation (RFC 8785) of this proof.
      #
      # @return [String]
      def to_json(*_args)
        CanonicalJSON.encode(to_hash)
      end

      # Returns the base64url encoding of the canonical JSON, suitable for use
      # as the +X402-Proof+ HTTP header value.
      #
      # @return [String]
      def to_header
        Encoding.base64url_encode(to_json)
      end

      # Decodes the raw transaction bytes from +payment['rawtx_b64']+.
      # The transaction is encoded as standard base64 (not base64url).
      #
      # @return [String] binary string of transaction bytes
      # @raise [BSV::X402::EncodingError] if the base64 is malformed
      def decoded_tx
        Encoding.base64_decode(payment['rawtx_b64'])
      end

      # Verifies that +payment['txid']+ matches the double-SHA-256 of the raw
      # transaction bytes in reversed byte order (standard Bitcoin txid format).
      #
      # @return [Boolean]
      def valid_txid?
        raw  = decoded_tx
        hash = BSV::Primitives::Digest.sha256d(raw)
        # Bitcoin txid is the double-SHA-256 hash with bytes reversed.
        computed_txid = hash.reverse.unpack1('H*')
        computed_txid == payment['txid']
      end

      # Returns a plain hash with string keys for JSON serialisation.
      #
      # @return [Hash]
      def to_hash
        {
          'challenge_sha256' => challenge_sha256,
          'payment' => payment,
          'request' => request,
          'scheme' => scheme,
          'v' => v
        }
      end

      private

      def validate!
        raise ValidationError, "proof.v must be #{SUPPORTED_VERSION}" unless v == SUPPORTED_VERSION
        raise ValidationError, "proof.scheme must be '#{SCHEME}'" unless scheme == SCHEME
        raise ValidationError, 'proof missing required field: challenge_sha256' if challenge_sha256.nil? || challenge_sha256.empty?

        validate_request!
        validate_payment!
      end

      def validate_request!
        raise ValidationError, 'proof missing required field: request' unless request.is_a?(Hash)

        %w[method path query req_headers_sha256 req_body_sha256].each do |field|
          value = request[field] || request[field.to_sym]
          raise ValidationError, "proof.request missing required field: #{field}" if value.nil?
        end
      end

      def validate_payment!
        raise ValidationError, 'proof missing required field: payment' unless payment.is_a?(Hash)

        %w[txid rawtx_b64].each do |field|
          value = payment[field] || payment[field.to_sym]
          raise ValidationError, "proof.payment missing required field: #{field}" if value.nil? || value.to_s.empty?
        end
      end

      def self.from_hash(hash)
        request_hash = fetch(hash, 'request')
        payment_hash = fetch(hash, 'payment')

        normalise = ->(h) { h.transform_keys(&:to_s) }

        new(
          v: fetch(hash, 'v'),
          scheme: fetch(hash, 'scheme'),
          challenge_sha256: fetch(hash, 'challenge_sha256'),
          request: normalise.call(request_hash),
          payment: normalise.call(payment_hash)
        )
      end
      private_class_method :from_hash

      def self.fetch(hash, key)
        return hash[key] if hash.key?(key)
        return hash[key.to_sym] if hash.key?(key.to_sym)

        raise ValidationError, "proof missing required field: #{key}"
      end
      private_class_method :fetch
    end
  end
end
