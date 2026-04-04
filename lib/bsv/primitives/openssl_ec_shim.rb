# frozen_string_literal: true

# OpenSSL EC shim — replaces OpenSSL's EC point arithmetic with the pure
# Ruby {BSV::Primitives::Secp256k1} engine while keeping real OpenSSL for
# BN, Digest, HMAC, Cipher, etc.
#
# Load order matters: real OpenSSL is loaded first so that BN and the
# symmetric-crypto classes are available, then the EC classes are
# redefined to delegate to our Secp256k1 module.

require 'openssl'

# Ensure the Secp256k1 module is loaded before we reference it.
require_relative 'secp256k1'

module OpenSSL
  module PKey
    # Minimal replacement for OpenSSL::PKey::EC that wraps a public key
    # point. Only the subset used by the SDK is implemented.
    class EC
      # @return [OpenSSL::PKey::EC::Point] the public key point
      attr_reader :public_key

      # Construct an EC key object.
      #
      # Accepts either DER-encoded bytes (for compatibility with the
      # existing +ec_key_from_*+ helpers) or an internal keyword to
      # wrap an already-constructed shim Point.
      def initialize(der_or_point)
        if der_or_point.is_a?(Point)
          @public_key = der_or_point
        elsif der_or_point.is_a?(String)
          @public_key = self.class.parse_der(der_or_point)
        else
          raise ArgumentError, "unsupported argument: #{der_or_point.class}"
        end
      end

      # Parse a DER-encoded EC key (SEC 1 private or SPKI public) and
      # extract the public key point.
      #
      # @param der [String] DER bytes
      # @return [Point]
      def self.parse_der(der)
        der = der.b
        # Detect format by the outer tag
        seq = OpenSSL::ASN1.decode(der)

        if seq.value[0].is_a?(OpenSSL::ASN1::Integer) && seq.value[0].value == 1
          # SEC 1 private key: SEQUENCE { INTEGER 1, OCTET STRING key, [0] OID, [1] BIT STRING pubkey }
          priv_bytes = seq.value[1].value
          scalar = BSV::Primitives::Secp256k1.bytes_to_int(priv_bytes)
          secp_point = BSV::Primitives::Secp256k1::Point.generator.mul(scalar)
          group = Group.new('secp256k1')
          Point.from_secp_point(group, secp_point)
        else
          # SPKI public key: SEQUENCE { SEQUENCE { OID, OID }, BIT STRING pubkey }
          pub_bytes = seq.value[1].value
          # BIT STRING has a leading unused-bits byte
          pub_bytes = pub_bytes[1..] if pub_bytes.getbyte(0).zero? && pub_bytes.length > 33
          secp_point = BSV::Primitives::Secp256k1::Point.from_bytes(pub_bytes)
          group = Group.new('secp256k1')
          Point.from_secp_point(group, secp_point)
        end
      end

      # The secp256k1 curve group.
      #
      # Implements only the methods used by the SDK: {#order} and
      # {#generator}.
      class Group
        # @param curve_name [String] must be +'secp256k1'+
        # @raise [ArgumentError] if the curve is not secp256k1
        def initialize(curve_name)
          raise ArgumentError, "unsupported curve: #{curve_name}" unless curve_name == 'secp256k1'
        end

        # The curve order N as an OpenSSL::BN.
        #
        # @return [OpenSSL::BN]
        def order
          @order ||= OpenSSL::BN.new(BSV::Primitives::Secp256k1::N.to_s)
        end

        # The generator point G.
        #
        # @return [Point]
        def generator
          @generator ||= Point.from_secp_point(self, BSV::Primitives::Secp256k1::Point.generator)
        end

        # @return [String]
        def curve_name
          'secp256k1'
        end
      end

      # Shim replacement for OpenSSL::PKey::EC::Point.
      #
      # Wraps a {BSV::Primitives::Secp256k1::Point} and exposes the
      # same interface that the SDK's consumer code expects.
      class Point
        # Error raised for invalid point operations (matches OpenSSL).
        class Error < OpenSSL::OpenSSLError; end

        # @return [Group] the curve group
        attr_reader :group

        # Construct a Point from a Group and an OpenSSL::BN encoding.
        #
        # This matches the OpenSSL API:
        #   Point.new(GROUP, OpenSSL::BN.new(bytes, 2))
        #
        # @param group [Group] the curve group
        # @param bn [OpenSSL::BN, nil] BN-encoded point bytes, or nil for generator
        def initialize(group, bn = nil)
          @group = group
          if bn.nil?
            # Match OpenSSL: Point.new(group) creates an uninitialised point.
            # Callers use set_to_infinity! or assign later.
            @secp_point = BSV::Primitives::Secp256k1::Point.infinity
          else
            bytes = bn.to_s(2)
            begin
              @secp_point = BSV::Primitives::Secp256k1::Point.from_bytes(bytes)
            rescue ArgumentError => e
              raise Error, e.message
            end
          end
        end

        # Internal constructor from an existing Secp256k1::Point.
        #
        # @param group [Group]
        # @param secp_point [BSV::Primitives::Secp256k1::Point]
        # @return [Point]
        def self.from_secp_point(group, secp_point)
          pt = allocate
          pt.instance_variable_set(:@group, group)
          pt.instance_variable_set(:@secp_point, secp_point)
          pt
        end

        # Scalar multiplication, or multi-scalar multiplication.
        #
        # Single-argument form: +point.mul(scalar_bn)+
        # Multi-argument form:  +point.mul([bn0, bn1], [point1])+
        #   computes bn0*self + bn1*point1
        #
        # @return [Point]
        def mul(*args)
          if args.length == 1
            # point.mul(scalar_bn)
            scalar = bn_to_int(args[0])
            result = @secp_point.mul(scalar)
            self.class.from_secp_point(@group, result)
          elsif args.length == 2
            # point.mul([bns], [points]) — multi-scalar
            bns = args[0]
            points = args[1]
            # result = bns[0]*self + bns[1]*points[0] + ...
            result = @secp_point.mul(bn_to_int(bns[0]))
            points.each_with_index do |pt, i|
              term = pt.instance_variable_get(:@secp_point).mul(bn_to_int(bns[i + 1]))
              result = result.add(term)
            end
            self.class.from_secp_point(@group, result)
          else
            raise ArgumentError, "wrong number of arguments (given #{args.length}, expected 1 or 2)"
          end
        end

        # Point addition.
        #
        # @param other [Point]
        # @return [Point]
        def add(other)
          result = @secp_point.add(other.instance_variable_get(:@secp_point))
          self.class.from_secp_point(@group, result)
        end

        # Serialise to SEC 1 compressed or uncompressed format.
        #
        # @param format [:compressed, :uncompressed]
        # @return [String] binary string (33 or 65 bytes)
        def to_octet_string(format = :compressed)
          @secp_point.to_octet_string(format)
        end

        # Convert to an OpenSSL::BN (the numeric encoding of the point bytes).
        #
        # This is used by tests: +point.to_bn(:compressed).to_s(16)+
        #
        # @param format [:compressed, :uncompressed]
        # @return [OpenSSL::BN]
        def to_bn(format = :compressed)
          OpenSSL::BN.new(to_octet_string(format), 2)
        end

        # Whether this is the point at infinity.
        #
        # @return [Boolean]
        def infinity?
          @secp_point.infinity?
        end

        # Set this point to the point at infinity (in-place).
        #
        # @return [self]
        def set_to_infinity!
          @secp_point = BSV::Primitives::Secp256k1::Point.infinity
          self
        end

        private

        def bn_to_int(bn)
          if bn.is_a?(OpenSSL::BN)
            BSV::Primitives::Secp256k1.bytes_to_int(bn.to_s(2))
          elsif bn.is_a?(Integer)
            bn
          else
            raise ArgumentError, "expected OpenSSL::BN or Integer, got #{bn.class}"
          end
        end
      end
    end
  end
end
