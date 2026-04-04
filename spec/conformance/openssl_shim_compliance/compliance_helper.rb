# frozen_string_literal: true

# Compliance helper — captures real OpenSSL EC classes before the shim
# replaces them, so we can compare both implementations side by side.
#
# IMPORTANT: This file must be loaded BEFORE spec_helper / bsv-sdk, which
# triggers the shim via Curve's autoload.

require 'openssl'
require 'securerandom'

# Save references to the real (C-backed) OpenSSL EC classes.
module OpenSSLCompliance
  RealGroup = OpenSSL::PKey::EC::Group
  RealPoint = OpenSSL::PKey::EC::Point
  RealEC    = OpenSSL::PKey::EC

  # The curve order N.
  N = RealGroup.new('secp256k1').order

  # Three deterministic scalars covering edge cases, plus one random.
  SCALAR_1    = OpenSSL::BN.new('1')
  SCALAR_MID  = OpenSSL::BN.new('DEADBEEF12345678', 16)
  SCALAR_HIGH = N - OpenSSL::BN.new('1')
  SCALAR_RAND = OpenSSL::BN.new(SecureRandom.random_bytes(32), 2) % (N - OpenSSL::BN.new('2')) + OpenSSL::BN.new('1')

  SCALARS = {
    'minimum (1)' => SCALAR_1,
    'mid-range' => SCALAR_MID,
    'maximum (N-1)' => SCALAR_HIGH,
    'random' => SCALAR_RAND
  }.freeze

  # Build a real OpenSSL group and generator for reference operations.
  def self.real_group
    @real_group ||= RealGroup.new('secp256k1')
  end

  def self.real_generator
    @real_generator ||= real_group.generator
  end

  # Compute a real OpenSSL point: scalar * G.
  def self.real_mul_generator(scalar_bn)
    real_generator.mul(scalar_bn)
  end
end

# NOW load the SDK (which sets up autoloads but doesn't trigger the shim yet).
require 'spec_helper'

# Force the Curve autoload, which loads the shim and replaces EC classes.
BSV::Primitives::Curve
