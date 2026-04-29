# frozen_string_literal: true

require_relative 'openssl_ec_shim'

module BSV
  module Primitives
    # Low-level secp256k1 elliptic curve operations.
    #
    # Backed by the pure Ruby {Secp256k1} module via an OpenSSL
    # compatibility shim. The shim preserves the +OpenSSL::PKey::EC+
    # interface so consumer code is unchanged. All constants and
    # methods operate on the secp256k1 curve.
    module Curve
      # The secp256k1 curve group.
      GROUP  = OpenSSL::PKey::EC::Group.new('secp256k1')

      # The curve order (number of points on the curve).
      N      = GROUP.order

      # The generator point (base point).
      G      = GROUP.generator

      # Half the curve order, used for low-S normalisation.
      HALF_N = (N >> 1)

      module_function

      # Multiply the generator point by a scalar (constant-time).
      #
      # Uses the Montgomery ladder by default, matching OpenSSL convention.
      # Safe for both secret and public scalars. For explicit variable-time
      # multiplication of public scalars, use {multiply_generator_vt}.
      #
      # @param scalar_bn [OpenSSL::BN] the scalar multiplier
      # @return [OpenSSL::PKey::EC::Point] the resulting curve point
      def multiply_generator(scalar_bn)
        G.mul(scalar_bn)
      end

      # Multiply the generator point by a secret scalar (constant-time).
      #
      # Alias for {multiply_generator} — retained for backward compatibility
      # and expressiveness.
      #
      # @param scalar_bn [OpenSSL::BN] the secret scalar multiplier
      # @return [OpenSSL::PKey::EC::Point] the resulting curve point
      def multiply_generator_ct(scalar_bn)
        G.mul(scalar_bn)
      end

      # Multiply the generator point by a public scalar (variable-time, wNAF).
      #
      # Faster than {multiply_generator} but leaks timing information about
      # the scalar. Use only for public scalars (e.g. signature verification).
      #
      # @param scalar_bn [OpenSSL::BN] the public scalar multiplier
      # @return [OpenSSL::PKey::EC::Point] the resulting curve point
      def multiply_generator_vt(scalar_bn)
        G.mul_vt(scalar_bn)
      end

      # Multiply an arbitrary curve point by a scalar (constant-time).
      #
      # Uses the Montgomery ladder by default, matching OpenSSL convention.
      # Safe for both secret and public scalars. For explicit variable-time
      # multiplication of public scalars, use {multiply_point_vt}.
      #
      # @param point [OpenSSL::PKey::EC::Point] the point to multiply
      # @param scalar_bn [OpenSSL::BN] the scalar multiplier
      # @return [OpenSSL::PKey::EC::Point] the resulting curve point
      def multiply_point(point, scalar_bn)
        point.mul(scalar_bn)
      end

      # Multiply an arbitrary curve point by a secret scalar (constant-time).
      #
      # Alias for {multiply_point} — retained for backward compatibility
      # and expressiveness.
      #
      # @param point [OpenSSL::PKey::EC::Point] the base point
      # @param scalar_bn [OpenSSL::BN] the secret scalar multiplier
      # @return [OpenSSL::PKey::EC::Point] the resulting curve point
      def multiply_point_ct(point, scalar_bn)
        point.mul(scalar_bn)
      end

      # Multiply an arbitrary curve point by a public scalar (variable-time, wNAF).
      #
      # Faster than {multiply_point} but leaks timing information about
      # the scalar. Use only for public scalars (e.g. signature verification).
      #
      # @param point [OpenSSL::PKey::EC::Point] the point to multiply
      # @param scalar_bn [OpenSSL::BN] the public scalar multiplier
      # @return [OpenSSL::PKey::EC::Point] the resulting curve point
      def multiply_point_vt(point, scalar_bn)
        point.mul_vt(scalar_bn)
      end

      # Add two curve points together.
      #
      # Uses +Point#add+ where available (Ruby 3.0+ / OpenSSL 3), falling
      # back to multi-scalar multiplication for Ruby 2.7 compatibility.
      #
      # @param point_a [OpenSSL::PKey::EC::Point] first point
      # @param point_b [OpenSSL::PKey::EC::Point] second point
      # @return [OpenSSL::PKey::EC::Point] the sum of the two points
      def add_points(point_a, point_b)
        if point_a.respond_to?(:add)
          point_a.add(point_b)
        else
          # Ruby 2.7 / OpenSSL < 3: use multi-scalar mul
          # point_a.mul(bns, points) = bns[0]*point_a + bns[1]*points[0] + ...
          one = OpenSSL::BN.new('1')
          point_a.mul([one, one], [point_b])
        end
      end

      # Extract the x-coordinate from a curve point as a big number.
      #
      # @param point [OpenSSL::PKey::EC::Point] the curve point
      # @return [OpenSSL::BN] the x-coordinate
      def point_x(point)
        # Uncompressed octet string: 0x04 || X (32 bytes) || Y (32 bytes)
        # Slicing raw bytes avoids BN#to_s(16) stripping leading zeros.
        OpenSSL::BN.new(point.to_octet_string(:uncompressed)[1, 32], 2)
      end

      # Reconstruct a curve point from its byte representation.
      #
      # @param bytes [String] compressed (33 bytes) or uncompressed (65 bytes) point encoding
      # @return [OpenSSL::PKey::EC::Point] the decoded curve point
      def point_from_bytes(bytes)
        OpenSSL::PKey::EC::Point.new(GROUP, OpenSSL::BN.new(bytes, 2))
      end
    end
  end
end
