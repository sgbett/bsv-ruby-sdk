# frozen_string_literal: true

# Micro-benchmark: BSV::Primitives::Digest.sha256d context reuse.
#
# Part of HLR #882 — Primitives::Digest: reuse OpenSSL contexts.
# Run from the gem/bsv-sdk/ directory: ruby bench/sha256d_reuse.rb
#
# Measures cache-warm vs cache-cold sha256d per call.
#
# "Cache-cold" means Thread.current[:bsv_sdk_sha256_digest] is set to nil
# immediately before the measured call, forcing OpenSSL::Digest::SHA256.new
# (and the EVP_get_digestbyname namemap lookup) on each iteration.
# "Cache-warm" is the normal production path — context already cached.
#
# Expected improvement: 1.4–2.0× per call.

require 'bundler/setup'
require 'benchmark/ips'
require 'openssl'
require 'securerandom'
require_relative '../lib/bsv-sdk'

input = SecureRandom.random_bytes(32)

# Warm the cache once so the warm path doesn't measure first-call allocation.
BSV::Primitives::Digest.sha256d(input)

puts "Ruby #{RUBY_VERSION} | OpenSSL #{OpenSSL::VERSION} (#{OpenSSL::OPENSSL_VERSION})"
puts 'Input: 32 random bytes | Comparing cache-cold vs cache-warm sha256d'
puts

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report('sha256d cache-cold') do
    # Force re-allocation on every call — simulates the pre-#882 behaviour.
    Thread.current[:bsv_sdk_sha256_digest] = nil
    BSV::Primitives::Digest.sha256d(input)
  end

  x.report('sha256d cache-warm') do
    BSV::Primitives::Digest.sha256d(input)
  end

  x.compare!
end
