# frozen_string_literal: true

require 'openssl'

module BSV
  module Storage
    # Helpers for encoding and decoding UHRP (Unified Hash Resource Protocol) URLs.
    #
    # A UHRP URL is a Base58Check string with a two-byte `\xCE\x00` prefix prepended
    # to the SHA-256 hash of the content. This makes each URL self-verifying and
    # stable across storage providers.
    #
    # == URL normalisation
    #
    # `normalize_url` strips the `uhrp:` scheme (case-insensitive) and the optional
    # `//` authority prefix, matching the TS SDK contract exactly. The `web+uhrp://`
    # variant used by some browser extension manifests is *not* normalised here — that
    # diverges from the TS reference (Python normalises it; we follow TS).
    module Utils
      # Two-byte UHRP version prefix: 0xCE 0x00.
      UHRP_PREFIX = "\xCE\x00".b.freeze

      module_function

      # Encode a 32-byte binary SHA-256 hash as a UHRP URL.
      #
      # @param hash [String] 32-byte binary string (SHA-256 hash)
      # @return [String] Base58Check-encoded UHRP URL
      # @raise [ArgumentError] if hash is not exactly 32 bytes
      def get_url_for_hash(hash)
        raise ArgumentError, 'Hash length must be 32 bytes (sha256)' unless hash.bytesize == 32

        BSV::Primitives::Base58.check_encode(hash.b, prefix: UHRP_PREFIX)
      end

      # Compute the SHA-256 hash of +data+ and encode it as a UHRP URL.
      #
      # @param data [String] binary file content
      # @return [String] Base58Check-encoded UHRP URL
      def get_url_for_file(data)
        hash = BSV::Primitives::Digest.sha256(data.b)
        get_url_for_hash(hash)
      end

      # Decode a UHRP URL and return the 32-byte binary SHA-256 hash.
      #
      # Accepts URLs with or without the `uhrp:` scheme and optional `//` authority.
      #
      # @param url [String] UHRP URL (with or without `uhrp:` prefix)
      # @return [String] 32-byte binary SHA-256 hash
      # @raise [ArgumentError] if the URL is not a String, empty, has a bad prefix, or has wrong length
      # @raise [BSV::Primitives::Base58::ChecksumError] if the Base58Check checksum fails
      def get_hash_from_url(url)
        raise ArgumentError, 'URL must be a String' unless url.is_a?(String)
        raise ArgumentError, 'URL must not be empty' if url.empty?

        normalised = normalize_url(url)
        result = BSV::Primitives::Base58.check_decode(normalised, prefix_length: 2)
        raise ArgumentError, 'Bad prefix' unless result[:prefix] == UHRP_PREFIX
        raise ArgumentError, 'Invalid length!' unless result[:data].bytesize == 32

        result[:data]
      end

      # Strip the `uhrp:` scheme (case-insensitive) and optional `//` from a URL.
      #
      # Follows the TS SDK contract: only `uhrp:` and `uhrp://` are normalised.
      # `web+uhrp://` is deliberately not stripped (TS does not strip it; Python does).
      #
      # @param url [String] URL to normalise
      # @return [String] normalised URL
      def normalize_url(url)
        url = url.slice(5..) if url.downcase.start_with?('uhrp:')
        url = url.slice(2..) if url.start_with?('//')
        url
      end

      # Return +true+ if +url+ is a syntactically valid UHRP URL.
      #
      # @param url [String] URL to validate
      # @return [Boolean]
      def valid_url?(url)
        get_hash_from_url(url)
        true
      rescue ArgumentError, BSV::Primitives::Base58::ChecksumError
        false
      end
    end
  end
end
