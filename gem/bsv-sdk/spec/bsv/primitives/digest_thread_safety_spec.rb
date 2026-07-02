# frozen_string_literal: true

require 'spec_helper'

# Thread-safety regression harness for HLR #882 — OpenSSL digest context reuse.
#
# BSV::Primitives::Digest caches one OpenSSL::Digest instance per algorithm
# per fibre in Thread.current (fibre-local in MRI).  This spec verifies that
# context reuse does not corrupt output across threads or fibres.
#
# Bit-equivalence (correct output values) is the responsibility of
# digest_spec.rb and digest_vectors_spec.rb — those specs remain the
# authoritative gate for correctness.  This spec asserts specifically that
# the caching pattern does not introduce cross-thread or cross-fibre state
# contamination.
#
# Design notes:
# - No sleep, Thread.pass, or timing assertions — results collected via
#   Queue (thread-safe) and compared against pre-computed vectors.
# - All scenarios are fully deterministic.

# Pre-computed reference vectors for thread-safety cross-checking.
# Defined outside the describe block to avoid RSpec/LeakyConstantDeclaration.
DIGEST_TS_VECTORS = {
  sha256_abc: BSV::Primitives::Digest.sha256('abc').freeze,
  sha256d_abc: BSV::Primitives::Digest.sha256d('abc').freeze,
  sha1_abc: BSV::Primitives::Digest.sha1('abc').freeze,
  sha512_abc: BSV::Primitives::Digest.sha512('abc').freeze,
  sha256_xy: BSV::Primitives::Digest.sha256('xy').freeze,
  sha256d_xy: BSV::Primitives::Digest.sha256d('xy').freeze,
  sha1_xy: BSV::Primitives::Digest.sha1('xy').freeze,
  sha512_xy: BSV::Primitives::Digest.sha512('xy').freeze
}.freeze

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'BSV::Primitives::Digest thread safety' do
  subject(:digest) { BSV::Primitives::Digest }

  # ---------------------------------------------------------------------------
  # Scenario 1 — cross-thread state-leak
  #
  # 16 threads × 1000 iterations.  Each thread mixes all four algorithms per
  # iteration (not one-algo-per-thread) — exercises cross-algorithm collision
  # within a thread's cache.  All results are compared to pre-computed vectors.
  # ---------------------------------------------------------------------------
  describe 'cross-thread state-leak (Scenario 1)' do
    it 'produces correct output across 16 threads × 1000 iterations of mixed algorithms' do
      errors = Queue.new

      threads = 16.times.map do
        Thread.new do
          1000.times do
            # Capture each digest result once — if the check fails we want the
            # recorded `got` payload to be *exactly* the value that failed,
            # not a recomputed value that may differ under transient
            # contamination.
            r256 = digest.sha256('abc')
            errors << [:sha256, r256, DIGEST_TS_VECTORS[:sha256_abc]] unless r256 == DIGEST_TS_VECTORS[:sha256_abc]

            r256d = digest.sha256d('abc')
            errors << [:sha256d, r256d, DIGEST_TS_VECTORS[:sha256d_abc]] unless r256d == DIGEST_TS_VECTORS[:sha256d_abc]

            r1 = digest.sha1('abc')
            errors << [:sha1, r1, DIGEST_TS_VECTORS[:sha1_abc]] unless r1 == DIGEST_TS_VECTORS[:sha1_abc]

            r512 = digest.sha512('abc')
            errors << [:sha512, r512, DIGEST_TS_VECTORS[:sha512_abc]] unless r512 == DIGEST_TS_VECTORS[:sha512_abc]
          end
        end
      end

      threads.each(&:join)

      collected = []
      collected << errors.pop until errors.empty?

      expect(collected).to be_empty,
                           "Cross-thread state contamination detected in #{collected.size} call(s): " \
                           "#{collected.first(3).map do |algo, got, exp|
                             "#{algo}: got #{got.unpack1('H*')[0, 8]}… expected #{exp.unpack1('H*')[0, 8]}…"
                           end.join('; ')}"
    end
  end

  # ---------------------------------------------------------------------------
  # Scenario 2 — same-thread post-exception
  #
  # Mock OpenSSL::Digest#update to raise on a specific call; verify that the
  # next call on the same thread produces the correct vector.  Proves the
  # leading reset cleanses any dirty state left by the exception.
  # ---------------------------------------------------------------------------
  describe 'same-thread post-exception (Scenario 2)' do
    it 'produces correct output on the call immediately following an exception' do
      call_count = 0
      raise_on = 3

      # Prime the cache with a fresh instance we can attach a singleton method
      # to.  Patching this specific instance (via define_singleton_method)
      # scopes the injected failure to just this cached context — no global
      # OpenSSL::Digest class-wide mutation, no residue for later specs.
      Thread.current[:bsv_sdk_sha256_digest] = nil
      digest.sha256('warmup')
      cached = Thread.current[:bsv_sdk_sha256_digest]
      original_update = cached.method(:update)

      cached.define_singleton_method(:update) do |data|
        call_count += 1
        raise 'injected failure' if call_count == raise_on

        original_update.call(data)
      end

      begin
        (raise_on + 2).times do |i|
          begin
            digest.sha256('abc')
          rescue RuntimeError
            # expected on call raise_on — swallow and continue
          end

          next unless i >= raise_on

          # First call after the injected failure must produce the correct vector.
          result = digest.sha256('abc')
          expect(result).to eq(DIGEST_TS_VECTORS[:sha256_abc]),
                            "Post-exception sha256 mismatch on iteration #{i}: " \
                            "got #{result.unpack1('H*')}"
        end
      ensure
        # Drop the singleton-patched instance so subsequent specs get a fresh,
        # unpatched OpenSSL::Digest on the next digest call.
        Thread.current[:bsv_sdk_sha256_digest] = nil
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Scenario 3 — interleaved large/small in same thread
  #
  # Alternate 1-byte and 1 MiB inputs 1000 times.  Catches large-payload state
  # leakage where a long message leaves residual compression state that then
  # corrupts a subsequent short message.
  # ---------------------------------------------------------------------------
  describe 'interleaved large/small inputs in same thread (Scenario 3)' do
    it 'produces correct output when alternating 1-byte and 1-MiB inputs 1000×' do
      large_input = 'a' * 1_048_576
      small_input = 'x'

      large_expected = digest.sha256(large_input)
      small_expected = digest.sha256(small_input)

      1000.times do |i|
        if i.even?
          result = digest.sha256(large_input)
          expect(result).to eq(large_expected), "Large-input mismatch on iteration #{i}"
        else
          result = digest.sha256(small_input)
          expect(result).to eq(small_expected), "Small-input mismatch on iteration #{i}"
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Scenario 4 — Fibre-yield paranoia
  #
  # Two Fibres on one thread, each computing sha256d and yielding between calls
  # (not mid-hash — that is not a valid interruption point).  Both fibres must
  # produce correct vectors.
  #
  # Documents that Thread.current[:key] is *fibre-local* in MRI: each Fibre
  # has its own cached context, so interleaved Fibre execution cannot
  # contaminate another Fibre's context.
  # ---------------------------------------------------------------------------
  describe 'Fibre-yield paranoia (Scenario 4)' do
    it 'produces correct output from two interleaved Fibres yielding between sha256d calls' do
      results_a = []
      results_b = []

      fibre_a = Fiber.new do
        100.times do
          results_a << digest.sha256d('abc')
          Fiber.yield
        end
      end

      fibre_b = Fiber.new do
        100.times do
          results_b << digest.sha256d('xy')
          Fiber.yield
        end
      end

      # Interleave: a, b, a, b, …
      200.times { |i| i.even? ? fibre_a.resume : fibre_b.resume }

      expect(results_a.length).to eq(100)
      expect(results_b.length).to eq(100)

      expect(results_a).to all(eq(DIGEST_TS_VECTORS[:sha256d_abc])),
                           'Fibre A produced incorrect sha256d output'
      expect(results_b).to all(eq(DIGEST_TS_VECTORS[:sha256d_xy])),
                           'Fibre B produced incorrect sha256d output'
    end
  end

  # ---------------------------------------------------------------------------
  # Thread-identity assertion
  #
  # Each thread's :bsv_sdk_sha256_digest object_id must be distinct from every
  # other thread's — confirms the cache is per-thread, not a shared singleton.
  # ---------------------------------------------------------------------------
  describe 'thread-identity assertion' do
    it 'allocates a distinct cached context object in each of 16 threads' do
      identity_queue = Queue.new

      threads = 16.times.map do
        Thread.new do
          # Warm the cache for this thread.
          digest.sha256('warmup')
          identity_queue << Thread.current[:bsv_sdk_sha256_digest].object_id
        end
      end

      threads.each(&:join)

      ids = []
      ids << identity_queue.pop until identity_queue.empty?

      expect(ids.length).to eq(16)
      expect(ids.uniq.length).to eq(16),
                                 'Duplicate object_id found — threads are sharing a cached context'
    end
  end
end
# rubocop:enable RSpec/DescribeClass
