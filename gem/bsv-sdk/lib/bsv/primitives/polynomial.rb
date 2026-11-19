# frozen_string_literal: true

require 'openssl'

module BSV
  module Primitives
    # A polynomial defined by a set of points, evaluated using Lagrange interpolation.
    #
    # Used in Shamir's Secret Sharing Scheme to split and reconstruct a secret.
    # All arithmetic is performed in the finite field GF(P) where P is the
    # secp256k1 field prime.
    #
    # The secret is encoded as the y-value at x=0. Given +threshold+ distinct
    # points the polynomial can be evaluated at any x by Lagrange interpolation.
    #
    # @example Construct shares from a private key
    #   poly   = Polynomial.from_private_key(key, threshold: 2)
    #   share1 = poly.value_at(OpenSSL::BN.new('1'))
    #   share0 = poly.value_at(OpenSSL::BN.new('0'))  # recovers the secret
    class Polynomial
      include FieldMath

      P = PointInFiniteField::P

      # @return [Array<PointInFiniteField>] the defining points of the polynomial
      attr_reader :points

      # @return [Integer] the minimum number of shares needed to reconstruct the secret
      attr_reader :threshold

      # @param points    [Array<PointInFiniteField>] defining points
      # @param threshold [Integer] reconstruction threshold (defaults to points.length)
      def initialize(points, threshold = nil)
        @points    = points
        @threshold = threshold || points.length
      end

      # Build a polynomial whose y-intercept (secret) is the private key scalar.
      #
      # The first point is (0, key_scalar). The remaining +threshold-1+ points
      # have random coordinates in [0, P), providing the random coefficients of
      # the underlying polynomial.
      #
      # @param key       [PrivateKey] the private key to split
      # @param threshold [Integer]    the reconstruction threshold (minimum 2)
      # @return [Polynomial]
      def self.from_private_key(key, threshold:)
        secret_y = key.bn
        points   = [PointInFiniteField.new(OpenSSL::BN.new('0'), secret_y)]

        (threshold - 1).times do
          random_x = OpenSSL::BN.rand(256) % P
          random_y = OpenSSL::BN.rand(256) % P
          points << PointInFiniteField.new(random_x, random_y)
        end

        new(points, threshold)
      end

      # Evaluate the polynomial at x using Lagrange interpolation mod P.
      #
      # @param x [OpenSSL::BN] the x value at which to evaluate
      # @return  [OpenSSL::BN] the y value, in [0, P)
      def value_at(x)
        y = OpenSSL::BN.new('0')

        threshold.times do |i|
          term = points[i].y
          threshold.times do |j|
            next if i == j

            xi = points[i].x
            xj = points[j].x

            numerator   = umod(x - xj, P)
            denominator = umod(xi - xj, P)
            denom_inv   = denominator.mod_inverse(P)

            fraction = numerator.mod_mul(denom_inv, P)
            term     = term.mod_mul(fraction, P)
          end
          y = y.mod_add(term, P)
        end

        y
      end
    end
  end
end
