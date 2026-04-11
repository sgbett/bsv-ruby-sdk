# frozen_string_literal: true

# OpenSSL EC shim — replaces OpenSSL's EC point arithmetic with the pure
# Ruby {BSV::Primitives::Secp256k1} engine while keeping real OpenSSL for
# BN, Digest, HMAC, Cipher, etc.
#
# Load order matters: real OpenSSL is loaded first so that BN and the
# symmetric-crypto classes are available, then the EC classes are
# replaced (not reopened) to delegate to our Secp256k1 module.
#
# Multiple shim classes (Group, Point, EC) are deliberately co-located in
# this single file because they form one coordinated namespace replacement
# and must be loaded together for the swap to be coherent.
# rubocop:disable Style/OneClassPerFile

require 'openssl'

# Ensure the Secp256k1 module is loaded before we reference it.
require_relative 'secp256k1'

# -- Define shim classes outside the OpenSSL namespace first, then swap. --

# Shim Group for secp256k1.
class BSVShimECGroup
  def initialize(curve_name)
    raise ArgumentError, "unsupported curve: #{curve_name}" unless curve_name == 'secp256k1'
  end

  def order
    @order ||= OpenSSL::BN.new(BSV::Primitives::Secp256k1::N.to_s)
  end

  def generator
    @generator ||= BSVShimECPoint.from_secp_point(self, BSV::Primitives::Secp256k1::Point.generator)
  end

  def curve_name
    'secp256k1'
  end
end

# Shim Point wrapping BSV::Primitives::Secp256k1::Point.
class BSVShimECPoint
  class Error < OpenSSL::OpenSSLError; end

  attr_reader :group

  def initialize(group, bn = nil)
    @group = group
    if bn.nil?
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

  def self.from_secp_point(group, secp_point)
    pt = allocate
    pt.instance_variable_set(:@group, group)
    pt.instance_variable_set(:@secp_point, secp_point)
    pt
  end

  def mul(*args)
    if args.length == 1
      scalar = bn_to_int(args[0])
      result = @secp_point.mul(scalar)
      self.class.from_secp_point(@group, result)
    elsif args.length == 2
      bns = args[0]
      points = args[1]
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

  # Constant-time scalar multiplication via the Montgomery ladder.
  #
  # Delegates to {BSV::Primitives::Secp256k1::Point#mul_ct} to ensure
  # secret-scalar paths execute in constant time.
  #
  # @param scalar_bn [OpenSSL::BN, Integer] the secret scalar
  # @return [BSVShimECPoint]
  def mul_ct(scalar_bn)
    scalar = bn_to_int(scalar_bn)
    result = @secp_point.mul_ct(scalar)
    self.class.from_secp_point(@group, result)
  end

  def add(other)
    result = @secp_point.add(other.instance_variable_get(:@secp_point))
    self.class.from_secp_point(@group, result)
  end

  def to_octet_string(format = :compressed)
    @secp_point.to_octet_string(format)
  end

  def to_bn(format = :compressed)
    OpenSSL::BN.new(to_octet_string(format), 2)
  end

  def infinity?
    @secp_point.infinity?
  end

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

# Shim EC key wrapping a public key point.
#
# The DER-parsing constructor and +parse_der+ class method have been
# removed. They existed solely to support +Curve.ec_key_from_private_bytes+
# and +Curve.ec_key_from_public_bytes+, which were deleted in the A4
# crypto hardening pass (HLR #316). No production code path constructs
# a +BSVShimEC+ from DER any longer.
class BSVShimEC
  attr_reader :public_key

  def initialize(point)
    raise ArgumentError, "expected BSVShimECPoint, got #{point.class}" unless point.is_a?(BSVShimECPoint)

    @public_key = point
  end
end

# -- Replace OpenSSL's EC classes with our shims. --
# The originals are C-backed and cannot be reopened cleanly (C methods
# take precedence over Ruby methods). We replace the constants instead.

module OpenSSL
  module PKey
    remove_const :EC if const_defined?(:EC)
    EC = BSVShimEC

    class EC
      remove_const :Group if const_defined?(:Group)
      Group = BSVShimECGroup

      remove_const :Point if const_defined?(:Point)
      Point = BSVShimECPoint
    end
  end
end

# Ensure the Error class is accessible at the expected path.
BSVShimECPoint.const_set(:Error, BSVShimECPoint::Error) unless BSVShimECPoint.const_defined?(:Error)
# rubocop:enable Style/OneClassPerFile
