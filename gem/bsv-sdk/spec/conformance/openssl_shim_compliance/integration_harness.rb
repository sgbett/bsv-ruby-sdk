#!/usr/bin/env ruby
# frozen_string_literal: true

# Standalone harness for process-isolated shim compliance testing.
#
# Usage:
#   ruby integration_harness.rb openssl /tmp/openssl_out
#   ruby integration_harness.rb shim    /tmp/shim_out
#
# Exercises every EC operation with deterministic inputs and writes each
# result to a separate file. When run with both backends, the output
# directories should be byte-identical.

require 'fileutils'

mode = ARGV[0]
output_dir = ARGV[1]

unless %w[openssl shim].include?(mode) && output_dir
  warn "Usage: #{$PROGRAM_NAME} <openssl|shim> <output_dir>"
  exit 1
end

FileUtils.mkdir_p(output_dir)

case mode
when 'openssl'
  require 'openssl'
when 'shim'
  # Load Bundler so that path-dependent gems (e.g. secp256k1-native) are
  # resolvable in this subprocess. The Gemfile root is four levels up from
  # the harness (gem/bsv-sdk/spec/conformance/openssl_shim_compliance/).
  ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../../../../../Gemfile', __dir__)
  require 'bundler/setup'
  $LOAD_PATH.unshift("#{File.expand_path('../../../..', __dir__)}/lib")
  require 'bsv/primitives/openssl_ec_shim'
end

# --- Helpers ---

def write(dir, name, data)
  File.binwrite(File.join(dir, name), data)
end

def write_text(dir, name, text)
  File.write(File.join(dir, name), text)
end

# Extract x-coordinate as 32-byte big-endian from uncompressed point.
def point_x_bytes(point)
  point.to_octet_string(:uncompressed)[1, 32]
end

# Build SEC 1 private key DER.
def build_private_der(priv_bytes, pub_compressed)
  OpenSSL::ASN1::Sequence.new(
    [
      OpenSSL::ASN1::Integer.new(1),
      OpenSSL::ASN1::OctetString.new(priv_bytes),
      OpenSSL::ASN1::ObjectId.new('secp256k1', 0, :EXPLICIT),
      OpenSSL::ASN1::BitString.new(pub_compressed, 1, :EXPLICIT)
    ]
  ).to_der
end

# Build SPKI public key DER.
def build_public_der(pub_bytes)
  algorithm_id = OpenSSL::ASN1::Sequence.new(
    [
      OpenSSL::ASN1::ObjectId.new('id-ecPublicKey'),
      OpenSSL::ASN1::ObjectId.new('secp256k1')
    ]
  )
  OpenSSL::ASN1::Sequence.new([algorithm_id, OpenSSL::ASN1::BitString.new(pub_bytes)]).to_der
end

# Pad scalar BN to 32 bytes.
def bn_to_32(bn)
  raw = bn.to_s(2)
  raw = ("\x00".b * (32 - raw.bytesize)) + raw if raw.bytesize < 32
  raw
end

# --- Setup ---

group = OpenSSL::PKey::EC::Group.new('secp256k1')
n = group.order
g = group.generator

scalar_1    = OpenSSL::BN.new('1')
scalar_mid  = OpenSSL::BN.new('DEADBEEF12345678', 16)
scalar_high = n - OpenSSL::BN.new('1')
scalar_2    = OpenSSL::BN.new('2')

# --- Group operations ---

write(output_dir, 'group_order.bin', n.to_s(2))
write(output_dir, 'group_generator_compressed.bin', g.to_octet_string(:compressed))
write(output_dir, 'group_generator_uncompressed.bin', g.to_octet_string(:uncompressed))

# --- Scalar multiplication: G * scalar ---

{ '1' => scalar_1, 'mid' => scalar_mid, 'high' => scalar_high }.each do |label, scalar|
  pt = g.mul(scalar)
  write(output_dir, "mul_g_#{label}_compressed.bin", pt.to_octet_string(:compressed))
  write(output_dir, "mul_g_#{label}_uncompressed.bin", pt.to_octet_string(:uncompressed))
end

# --- Scalar multiplication: non-generator ---

two_g = g.mul(scalar_2)
pt = two_g.mul(scalar_mid)
write(output_dir, 'mul_nongen_compressed.bin', pt.to_octet_string(:compressed))
write(output_dir, 'mul_nongen_uncompressed.bin', pt.to_octet_string(:uncompressed))

# --- Point addition ---

p1 = g.mul(scalar_1)
p_mid = g.mul(scalar_mid)
p_high = g.mul(scalar_high)

sum_1_mid = p1.add(p_mid)
write(output_dir, 'add_1_mid_compressed.bin', sum_1_mid.to_octet_string(:compressed))

sum_mid_high = p_mid.add(p_high)
write(output_dir, 'add_mid_high_compressed.bin', sum_mid_high.to_octet_string(:compressed))

# P + (-P) = infinity
sum_1_neg = p1.add(p_high) # scalar_high = N-1, so (N-1)*G = -G
write_text(output_dir, 'add_1_high_infinity.txt', sum_1_neg.infinity?.to_s)

# --- Point x-coordinate extraction ---

write(output_dir, 'point_x_1.bin', point_x_bytes(p1))
write(output_dir, 'point_x_mid.bin', point_x_bytes(p_mid))

# --- to_bn ---

write(output_dir, 'to_bn_compressed_1.bin', p1.to_bn(:compressed).to_s(2))
write(output_dir, 'to_bn_compressed_mid.bin', p_mid.to_bn(:compressed).to_s(2))
write_text(output_dir, 'to_bn_hex_1.txt', p1.to_bn(:compressed).to_s(16))
write_text(output_dir, 'to_bn_hex_mid.txt', p_mid.to_bn(:compressed).to_s(16))

# --- EC key from DER ---
#
# NOTE: the ec_key_from_* helpers and the DER-parsing BSVShimEC constructor
# were removed in the A4 crypto hardening pass (HLR #316). The ec_key_priv_*
# and ec_key_pub_* output files are no longer generated. The integration_spec
# list of expected files has been updated accordingly.

# --- Done ---

file_count = Dir[File.join(output_dir, '*')].count
warn "#{mode}: wrote #{file_count} files to #{output_dir}"
