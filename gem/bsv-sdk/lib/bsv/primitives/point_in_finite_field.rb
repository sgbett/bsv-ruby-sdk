# frozen_string_literal: true

require 'openssl'

module BSV
  module Primitives
    # A point (x, y) in a finite field over the secp256k1 field prime P.
    #
    # Used as a share in Shamir's Secret Sharing Scheme. Both coordinates are
    # reduced modulo P on construction so they always lie in [0, P).
    #
    # Serialisation uses Base58 for each coordinate, joined by a dot, matching
    # the format used by the Go and TypeScript reference SDKs.
    #
    # @example
    #   point = PointInFiniteField.new(OpenSSL::BN.new(10), OpenSSL::BN.new(20))
    #   str   = point.to_s   #=> "C.N"
    #   back  = PointInFiniteField.from_string(str)
    class PointInFiniteField
      # The secp256k1 field prime P.
      P = OpenSSL::BN.new('FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F', 16).freeze

      # @return [OpenSSL::BN] the x-coordinate, reduced mod P
      attr_reader :x

      # @return [OpenSSL::BN] the y-coordinate, reduced mod P
      attr_reader :y

      # @param x [OpenSSL::BN] the x-coordinate
      # @param y [OpenSSL::BN] the y-coordinate
      def initialize(x, y)
        @x = umod(x, P)
        @y = umod(y, P)
      end

      # Serialise to Base58(x) + "." + Base58(y).
      #
      # @return [String] dot-separated Base58-encoded coordinates
      def to_s
        "#{Base58.encode(bn_to_bytes(@x))}.#{Base58.encode(bn_to_bytes(@y))}"
      end

      # Deserialise from a "Base58(x).Base58(y)" string.
      #
      # @param str [String] dot-separated Base58-encoded coordinates
      # @return [PointInFiniteField]
      # @raise [ArgumentError] if the string does not contain exactly one dot
      def self.from_string(str)
        parts = str.split('.')
        raise ArgumentError, "invalid point string: expected 'x.y', got #{str.inspect}" unless parts.length == 2

        x = OpenSSL::BN.new(Base58.decode(parts[0]), 2)
        y = OpenSSL::BN.new(Base58.decode(parts[1]), 2)
        new(x, y)
      end

      private

      # Unsigned modulo — always returns a non-negative result in [0, m).
      def umod(n, m)
        result = n % m
        result.negative? ? result + m : result
      end

      # Convert an OpenSSL::BN to a big-endian binary string, stripping the
      # sign byte that OpenSSL::BN#to_s(2) sometimes prepends.
      def bn_to_bytes(bn)
        bytes = bn.to_s(2)
        # BN(0).to_s(2) returns "" — encode as a single zero byte so
        # Base58 round-trip works (Base58.decode raises on empty strings).
        bytes.empty? ? "\x00".b : bytes
      end
    end
  end
end
