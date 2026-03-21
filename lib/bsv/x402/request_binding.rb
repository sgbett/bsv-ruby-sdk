# frozen_string_literal: true

module BSV
  module X402
    # Utilities for computing the request-binding hashes embedded in challenges
    # and proofs.
    #
    # The request-binding mechanism ties a challenge to a specific HTTP request
    # so that a proof cannot be replayed against a different request or path.
    module RequestBinding
      # Computes the SHA-256 hex digest for a set of HTTP headers.
      #
      # The canonical header string is built by:
      # 1. Lowercasing all header names
      # 2. Trimming leading/trailing whitespace from values
      # 3. Sorting headers by name in ascending byte order
      # 4. Concatenating as +name:value\n+ for each header
      #
      # This matches the binding format specified in the x402 implementation guide.
      #
      # @param headers [Hash] header name → value pairs (string or symbol keys)
      # @return [String] lowercase hex SHA-256 digest
      def self.compute_headers_hash(headers)
        normalised = headers.map { |(name, value)| "#{name.to_s.downcase}:#{value.to_s.strip}" }
        canonical  = normalised.sort.map { |line| "#{line}\n" }.join

        BSV::Primitives::Digest.sha256(canonical).unpack1('H*')
      end

      # Computes the SHA-256 hex digest of the request body bytes.
      #
      # An empty or nil body hashes to the SHA-256 of the empty string:
      # +e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855+
      #
      # @param body_bytes [String, nil] raw request body bytes
      # @return [String] lowercase hex SHA-256 digest
      def self.compute_body_hash(body_bytes)
        BSV::Primitives::Digest.sha256(body_bytes.to_s).unpack1('H*')
      end
    end
  end
end
