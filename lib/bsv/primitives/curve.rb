# frozen_string_literal: true

require 'openssl'

module BSV
  module Primitives
    module Curve
      GROUP  = OpenSSL::PKey::EC::Group.new('secp256k1')
      N      = GROUP.order
      G      = GROUP.generator
      HALF_N = (N >> 1)

      module_function

      def multiply_generator(scalar_bn)
        G.mul(scalar_bn)
      end

      def multiply_point(point, scalar_bn)
        point.mul(scalar_bn)
      end

      def add_points(point_a, point_b)
        point_a.add(point_b)
      end

      def point_x(point)
        x_hex = point.to_bn(:uncompressed).to_s(16)
        # Uncompressed format: 04 || X (64 hex) || Y (64 hex)
        OpenSSL::BN.new(x_hex[2, 64], 16)
      end

      def point_from_bytes(bytes)
        OpenSSL::PKey::EC::Point.new(GROUP, OpenSSL::BN.new(bytes, 2))
      end

      def ec_key_from_private_bytes(private_bytes)
        priv_bn = OpenSSL::BN.new(private_bytes, 2)
        pub_point = multiply_generator(priv_bn)

        asn1 = OpenSSL::ASN1::Sequence.new([
                                             OpenSSL::ASN1::Integer.new(1),
                                             OpenSSL::ASN1::OctetString.new(private_bytes),
                                             OpenSSL::ASN1::ObjectId.new('secp256k1', 0, :EXPLICIT),
                                             OpenSSL::ASN1::BitString.new(pub_point.to_octet_string(:compressed), 1,
                                                                          :EXPLICIT)
                                           ])
        OpenSSL::PKey::EC.new(asn1.to_der)
      end

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
