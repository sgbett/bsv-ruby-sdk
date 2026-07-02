# frozen_string_literal: true

# End-to-end benchmark: combined #881 (sighash cache) + #882 (digest context
# reuse) speedup on a realistic Tx#sighash hot path.
#
# Part of HLR #882 — Primitives::Digest: reuse OpenSSL contexts.
# See also: HLR #881 — Tx#sighash BIP-143 component memoisation.
# Run from the gem/bsv-sdk/ directory: ruby bench/tx_verify_end_to_end.rb
#
# Measures 10-input × 10-output Tx#sighash-for-all-inputs (the inner loop
# of a sign/verify workflow).
#
# "Cache-cold" simulates the pre-#882 environment: the per-thread digest
# context is cleared before every iteration, forcing EVP_get_digestbyname
# on each OpenSSL::Digest allocation.
# Thread.current[:bsv_sdk_sha256_digest] = nil is the exact cold-cache probe.
#
# sha256d call count (from #881 regression spec): 3 component hashes +
# 10 per-input preimage hashes = 13 total across all 10 sighash calls.
# Pre-#881 this was ~30 (hash_prevouts + hash_sequence + hash_outputs each
# recomputed per input). The combined improvement is call-count × per-call.

require 'bundler/setup'
require 'benchmark/ips'
require 'openssl'
require_relative '../lib/bsv-sdk'

BENCH_LOCK = BSV::Script::Script.from_asm(
  "OP_DUP OP_HASH160 #{'ab' * 20} OP_EQUALVERIFY OP_CHECKSIG"
)

def build_bench_tx(n_inputs: 10, n_outputs: 10)
  tx = BSV::Transaction::Tx.new

  n_inputs.times do |i|
    input = BSV::Transaction::TransactionInput.new(
      prev_wtxid: ([i].pack('V') + ("\x00".b * 28)),
      prev_tx_out_index: 0
    )
    input.source_satoshis = 1_000_000
    input.source_locking_script = BENCH_LOCK
    tx.add_input(input)
  end

  n_outputs.times do |i|
    tx.add_output(BSV::Transaction::TransactionOutput.new(
                    satoshis: 100_000 + i,
                    locking_script: BENCH_LOCK
                  ))
  end

  tx
end

# Count sha256d calls for one full sighash round to confirm #881 is in effect.
tx_probe = build_bench_tx
call_counter = 0
original_sha256d = BSV::Primitives::Digest.method(:sha256d)
BSV::Primitives::Digest.define_singleton_method(:sha256d) do |data|
  call_counter += 1
  original_sha256d.call(data)
end
begin
  10.times { |i| tx_probe.sighash(i, BSV::Transaction::Sighash::ALL_FORK_ID) }
ensure
  # Always restore — otherwise the counting singleton would linger and add
  # per-call dispatch overhead to every subsequent benchmark iteration,
  # skewing the cold/warm measurement.
  BSV::Primitives::Digest.define_singleton_method(:sha256d, original_sha256d)
end

puts "Ruby #{RUBY_VERSION} | OpenSSL #{OpenSSL::VERSION} (#{OpenSSL::OPENSSL_VERSION})"
puts 'Tx: 10 inputs × 10 outputs | sighash ALL|FORKID for all 10 inputs'
puts "sha256d call count per full sign round: #{call_counter} (expected 13 with #881)"
puts '(pre-#881 baseline was ~30; #882 reduces per-call cost of each)'
puts

# Build a single tx once so we don't pay tx-construction cost per iteration.
# Each iteration calls bench_tx.invalidate_caches below, so both cold and
# warm branches consistently exercise all 13 sha256d calls per round; the
# only variable between them is whether the per-thread OpenSSL::Digest
# context is present.
bench_tx = build_bench_tx

# Warm the memoisation cache and the digest context cache.
10.times { |i| bench_tx.sighash(i, BSV::Transaction::Sighash::ALL_FORK_ID) }
bench_tx.invalidate_caches
10.times { |i| bench_tx.sighash(i, BSV::Transaction::Sighash::ALL_FORK_ID) }

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report('sighash × 10 cache-cold digest') do
    # Simulate pre-#882: clear cached digest context before each full round.
    Thread.current[:bsv_sdk_sha256_digest] = nil
    bench_tx.invalidate_caches
    10.times { |i| bench_tx.sighash(i, BSV::Transaction::Sighash::ALL_FORK_ID) }
  end

  x.report('sighash × 10 cache-warm digest') do
    # Normal production path: digest context already cached.
    bench_tx.invalidate_caches
    10.times { |i| bench_tx.sighash(i, BSV::Transaction::Sighash::ALL_FORK_ID) }
  end

  x.compare!
end
