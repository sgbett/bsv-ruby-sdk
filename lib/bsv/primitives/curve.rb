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

      # Multiply the generator point by a scalar.
      #
      # @param scalar_bn [OpenSSL::BN] the scalar multiplier
      # @return [OpenSSL::PKey::EC::Point] the resulting curve point
      def multiply_generator(scalar_bn)
        G.mul(scalar_bn)
      end

      # Multiply an arbitrary curve point by a scalar.
      #
      # @param point [OpenSSL::PKey::EC::Point] the point to multiply
      # @param scalar_bn [OpenSSL::BN] the scalar multiplier
      # @return [OpenSSL::PKey::EC::Point] the resulting curve point
      def multiply_point(point, scalar_bn)
        point.mul(scalar_bn)
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

      # Build an +OpenSSL::PKey::EC+ key object from raw private key bytes.
      #
      # @param private_bytes [String] 32-byte big-endian private key
      # @return [OpenSSL::PKey::EC] an EC key with both private and public components
      def ec_key_from_private_bytes(private_bytes)
        priv_bn = OpenSSL::BN.new(private_bytes, 2)
        pub_point = multiply_generator(priv_bn)

        asn1 = OpenSSL::ASN1::Sequence.new([
                                             OpenSSL::ASN1::Integer.new(1),
                                             OpenSSL::ASN1::OctetString.new(private_bytes),
                                             OpenSSL::ASN1::ObjectId.new('secp256k1', 0, :EXPLICIT),
                                             OpenSSL::ASN1::BitString.new(pub_point.to_octet_string(:compressed), 1, :EXPLICIT)
                                           ])
        OpenSSL::PKey::EC.new(asn1.to_der)
      end

      # Build an +OpenSSL::PKey::EC+ key object from raw public key bytes.
      #
      # @param public_bytes [String] compressed (33) or uncompressed (65) public key bytes
      # @return [OpenSSL::PKey::EC] an EC key with only the public component
      def ec_key_from_public_bytes(public_bytes)
        asn1 = OpenSSL::ASN1::Sequence.new([
                                             OpenSSL::ASN1::Sequence.new([
                                                                           OpenSSL::ASN1::ObjectId.new('id-ecPublicKey'),
                                                                           OpenSSL::ASN1::ObjectId.new('secp256k1')
                                                                         ]),
                                             OpenSSL::ASN1::BitString.new(public_bytes)
                                           ])
        OpenSSL::PKey::EC.new(asn1.to_der)
      end
    end
  end
end
