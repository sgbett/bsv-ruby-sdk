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
  SCALAR_RAND = (OpenSSL::BN.new(SecureRandom.random_bytes(32), 2) % (N - OpenSSL::BN.new('2'))) + OpenSSL::BN.new('1')

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
BSV::Primitives.const_get(:Curve)

# The shim conformance suite compares our pure-Ruby implementation against
# stock OpenSSL on the same Ruby version. OpenSSL::PKey::EC::Point#add and
# the multi-scalar form of #mul were added in the openssl gem v3.0 (bundled
# with Ruby 3.1+), so on Ruby 2.7 the real-OpenSSL side of the comparison
# can't run. The shim itself is unaffected — it has direct unit-test coverage
# in spec/bsv/primitives/secp256k1_spec.rb that runs on every supported Ruby.
unless OpenSSLCompliance::RealPoint.method_defined?(:add)
  RSpec.configure do |config|
    config.define_derived_metadata(file_path: %r{spec/conformance/openssl_shim_compliance/}) do |meta|
      meta[:skip] = 'shim conformance suite requires openssl gem >= 3.0 (Ruby 3.1+)'
    end
  end
end
