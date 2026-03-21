# frozen_string_literal: true

require 'base64'

module BSV
  module X402
    # Encoding utilities for the x402 protocol.
    #
    # Provides URL-safe base64 (RFC 4648 §5) without padding, used for
    # X402-Challenge and X402-Proof headers, and standard base64 for
    # +rawtx_b64+ (transaction bytes in proof payment).
    module Encoding
      # Maximum permitted header size (64 KiB). Headers larger than this are
      # rejected to prevent denial-of-service via oversized inputs.
      MAX_HEADER_BYTES = 65_536

      # Encodes +data+ (String of bytes) to URL-safe base64 without padding.
      #
      # @param data [String] binary string
      # @return [String] base64url-encoded string
      def self.base64url_encode(data)
        Base64.urlsafe_encode64(data, padding: false)
      end

      # Decodes a URL-safe base64 string (with or without padding).
      #
      # @param str [String]
      # @return [String] decoded binary string
      # @raise [BSV::X402::EncodingError] if +str+ exceeds 64 KiB or is malformed
      def self.base64url_decode(str)
        raise EncodingError, 'header exceeds 64 KiB size limit' if str.bytesize > MAX_HEADER_BYTES

        # Ruby's strict decoder rejects padding errors; add padding if absent.
        padded = add_base64_padding(str)
        Base64.urlsafe_decode64(padded)
      rescue ArgumentError => e
        raise EncodingError, "invalid base64url encoding: #{e.message}"
      end

      # Encodes +data+ to standard base64 (used for +rawtx_b64+).
      #
      # @param data [String] binary string
      # @return [String] base64-encoded string (with padding)
      def self.base64_encode(data)
        Base64.strict_encode64(data)
      end

      # Decodes a standard base64 string.
      #
      # @param str [String]
      # @return [String] decoded binary string
      # @raise [BSV::X402::EncodingError] if +str+ is malformed
      def self.base64_decode(str)
        Base64.strict_decode64(str)
      rescue ArgumentError => e
        raise EncodingError, "invalid base64 encoding: #{e.message}"
      end

      # ------------------------------------------------------------------
      # Private helpers
      # ------------------------------------------------------------------

      # Adds the correct number of '=' padding characters so Ruby's decoder
      # accepts strings that were encoded without padding.
      def self.add_base64_padding(str)
        remainder = str.length % 4
        return str if remainder.zero?

        str + ('=' * (4 - remainder))
      end
      private_class_method :add_base64_padding
    end
  end
end
