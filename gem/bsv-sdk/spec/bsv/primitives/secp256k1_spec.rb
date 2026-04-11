# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Primitives::Secp256k1 do
  # Explicitly named (not `described_class`) so `s::GX` etc. resolves to
  # Secp256k1 inside nested `describe Secp256k1::Point` blocks, where
  # `described_class` would otherwise become Point and break constant lookup.
  let(:s) { BSV::Primitives::Secp256k1 } # rubocop:disable RSpec/DescribedClass

  describe 'constants' do
    it 'P is the secp256k1 field prime' do
      expect(s::P).to eq((2**256) - (2**32) - 977)
    end

    it 'N is the curve order' do
      expect(s::N).to eq(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141)
    end

    it 'HALF_N is N >> 1' do
      expect(s::HALF_N).to eq(s::N >> 1)
    end

    it 'G is on the curve (y^2 = x^3 + 7 mod P)' do
      lhs = s.fsqr(s::GY)
      rhs = s.fadd(s.fmul(s.fsqr(s::GX), s::GX), 7)
      expect(lhs).to eq(rhs)
    end
  end

  describe 'byte helpers' do
    it 'round-trips bytes_to_int and int_to_bytes' do
      n = 0xDEADBEEFCAFE
      bytes = s.int_to_bytes(n, 32)
      expect(bytes.length).to eq(32)
      expect(s.bytes_to_int(bytes)).to eq(n)
    end

    it 'preserves leading zeros' do
      n = 1
      bytes = s.int_to_bytes(n, 32)
      expect(bytes.getbyte(0)).to eq(0)
      expect(bytes.getbyte(31)).to eq(1)
    end

    it 'handles zero' do
      expect(s.bytes_to_int(s.int_to_bytes(0, 32))).to eq(0)
    end
  end

  describe 'field arithmetic' do
    it 'fmul produces correct result' do
      a = s::P - 1
      expect(s.fmul(a, a)).to eq((a * a) % s::P)
    end

    it 'fsqr matches fmul(a, a)' do
      a = 0xDEADBEEF12345678
      expect(s.fsqr(a)).to eq(s.fmul(a, a))
    end

    it 'fadd wraps around P' do
      expect(s.fadd(s::P - 1, 2)).to eq(1)
    end

    it 'fsub handles underflow' do
      expect(s.fsub(1, 3)).to eq(s::P - 2)
    end

    it 'fneg negates correctly' do
      expect(s.fadd(42, s.fneg(42))).to eq(0)
      expect(s.fneg(0)).to eq(0)
    end

    it 'finv produces a * a^-1 = 1' do
      a = 0x123456789ABCDEF
      expect(s.fmul(a, s.finv(a))).to eq(1)
    end

    it 'fsqrt finds correct root' do
      a = 42
      sq = s.fsqr(a)
      root = s.fsqrt(sq)
      expect(root).not_to be_nil
      # root could be a or P-a
      expect(s.fsqr(root)).to eq(sq)
    end

    it 'fsqrt returns nil for non-residue' do
      # 3 is not a quadratic residue mod P (secp256k1)
      expect(s.fsqrt(3)).to be_nil
    end
  end

  describe 'scalar arithmetic' do
    it 'scalar_mod handles negative values' do
      expect(s.scalar_mod(-1)).to eq(s::N - 1)
    end

    it 'scalar_inv produces a * a^-1 = 1 mod N' do
      a = 0xDEADBEEF
      expect(s.scalar_mul(a, s.scalar_inv(a))).to eq(1)
    end

    it 'scalar_add wraps around N' do
      expect(s.scalar_add(s::N - 1, 2)).to eq(1)
    end
  end

  describe 'WNAF_TABLE_CACHE LRU bound' do
    it 'defines WNAF_CACHE_MAX as 512' do
      expect(s::WNAF_CACHE_MAX).to eq(512)
    end

    it 'evicts the oldest entry when the cache is full' do
      cache = s::WNAF_TABLE_CACHE
      # Snapshot the cache and work on a fresh copy to avoid polluting state.
      saved = cache.dup
      cache.clear

      # Fill the cache to the limit using sentinel entries.
      s::WNAF_CACHE_MAX.times { |i| cache["5:sentinel_x_#{i}:sentinel_y_#{i}"] = [:dummy] }
      first_key = cache.keys.first
      expect(cache.size).to eq(s::WNAF_CACHE_MAX)

      # Simulate what scalar_multiply_wnaf does when the cache is full.
      cache.delete(cache.keys.first) if cache.size >= s::WNAF_CACHE_MAX
      cache['5:new_key:new_key'] = [:new]

      expect(cache.size).to eq(s::WNAF_CACHE_MAX)
      expect(cache.key?(first_key)).to be false
    ensure
      cache.clear
      cache.merge!(saved)
    end
  end

  describe 'Jacobian point operations' do
    let(:g_jp) { [s::GX, s::GY, 1] }

    it 'jp_double of G produces a valid point' do
      doubled = s.jp_double(g_jp)
      affine = s.jp_to_affine(doubled)
      expect(affine).not_to be_nil
      x, y = affine
      # Check on curve: y^2 = x^3 + 7
      expect(s.fsqr(y)).to eq(s.fadd(s.fmul(s.fsqr(x), x), 7))
    end

    it 'jp_add of G + G equals jp_double of G' do
      sum = s.jp_add(g_jp, g_jp)
      doubled = s.jp_double(g_jp)
      expect(s.jp_to_affine(sum)).to eq(s.jp_to_affine(doubled))
    end

    it 'jp_add with infinity returns the other point' do
      inf = described_class::JP_INFINITY
      expect(s.jp_to_affine(s.jp_add(inf, g_jp))).to eq([s::GX, s::GY])
      expect(s.jp_to_affine(s.jp_add(g_jp, inf))).to eq([s::GX, s::GY])
    end

    it 'jp_to_affine returns nil for infinity' do
      expect(s.jp_to_affine(described_class::JP_INFINITY)).to be_nil
    end
  end

  describe BSV::Primitives::Secp256k1::Point do
    describe '.generator' do
      it 'returns the secp256k1 generator point' do
        g = described_class.generator
        expect(g.x).to eq(s::GX)
        expect(g.y).to eq(s::GY)
        expect(g.infinity?).to be false
      end

      it 'is on the curve' do
        expect(described_class.generator.on_curve?).to be true
      end
    end

    describe '.infinity' do
      it 'creates the point at infinity' do
        inf = described_class.infinity
        expect(inf.infinity?).to be true
        expect(inf.x).to be_nil
        expect(inf.y).to be_nil
      end
    end

    describe '.from_bytes' do
      let(:g) { described_class.generator }
      let(:compressed) { g.to_octet_string(:compressed) }
      let(:uncompressed) { g.to_octet_string(:uncompressed) }

      it 'deserialises compressed format' do
        pt = described_class.from_bytes(compressed)
        expect(pt).to eq(g)
      end

      it 'deserialises uncompressed format' do
        pt = described_class.from_bytes(uncompressed)
        expect(pt).to eq(g)
      end

      it 'raises on invalid prefix' do
        expect { described_class.from_bytes("\u0001#{"\x00" * 32}") }.to raise_error(ArgumentError, /unknown point prefix/)
      end

      it 'raises on wrong length for compressed' do
        expect { described_class.from_bytes("\u0002#{"\x00" * 31}") }.to raise_error(ArgumentError, /invalid compressed/)
      end

      it 'raises on wrong length for uncompressed' do
        expect { described_class.from_bytes("\u0004#{"\x00" * 63}") }.to raise_error(ArgumentError, /invalid uncompressed/)
      end

      it 'raises on point not on curve' do
        bad = "\x04".b + s.int_to_bytes(1, 32) + s.int_to_bytes(2, 32)
        expect { described_class.from_bytes(bad) }.to raise_error(ArgumentError, /not on the curve/)
      end
    end

    describe '#to_octet_string' do
      let(:g) { described_class.generator }

      it 'compressed is 33 bytes' do
        expect(g.to_octet_string(:compressed).length).to eq(33)
      end

      it 'uncompressed is 65 bytes' do
        expect(g.to_octet_string(:uncompressed).length).to eq(65)
      end

      it 'round-trips through from_bytes' do
        %i[compressed uncompressed].each do |fmt|
          pt = described_class.from_bytes(g.to_octet_string(fmt))
          expect(pt).to eq(g)
        end
      end

      it 'raises for point at infinity' do
        expect { described_class.infinity.to_octet_string }.to raise_error(RuntimeError, /infinity/)
      end
    end

    describe '#mul' do
      let(:g) { described_class.generator }

      it '1 * G = G' do
        expect(g.mul(1)).to eq(g)
      end

      it '2 * G matches G + G' do
        two_g = g.mul(2)
        g_plus_g = g.add(g)
        expect(two_g).to eq(g_plus_g)
      end

      it '0 * G = infinity' do
        expect(g.mul(0).infinity?).to be true
      end

      it 'N * G = infinity' do
        expect(g.mul(s::N).infinity?).to be true
      end

      it '(N - 1) * G = -G' do
        result = g.mul(s::N - 1)
        expect(result.x).to eq(g.x)
        expect(result.y).to eq(s.fneg(g.y))
      end

      it 'produces known 2*G coordinates' do
        # Known 2*G for secp256k1
        two_g = g.mul(2)
        expect(two_g.x).to eq(0xC6047F9441ED7D6D3045406E95C07CD85C778E4B8CEF3CA7ABAC09B95C709EE5)
        expect(two_g.y).to eq(0x1AE168FEA63DC339A3C58419466CEAEEF7F632653266D0E1236431A950CFE52A)
      end

      it 'produces known 3*G coordinates' do
        three_g = g.mul(3)
        expect(three_g.x).to eq(0xF9308A019258C31049344F85F89D5229B531C845836F99B08601F113BCE036F9)
        expect(three_g.y).to eq(0x388F7B0F632DE8140FE337E62A37F3566500A99934C2231B6CB9FD7584B8E672)
      end

      it 'produces result on the curve' do
        result = g.mul(0xDEADBEEF)
        expect(result.on_curve?).to be true
      end

      it 'infinity * scalar = infinity' do
        expect(described_class.infinity.mul(42).infinity?).to be true
      end
    end

    describe '#mul_ct (Montgomery ladder, constant-time)' do
      let(:g) { described_class.generator }

      it 'produces the same result as mul for scalar 1' do
        expect(g.mul_ct(1)).to eq(g.mul(1))
      end

      it 'produces the same result as mul for scalar 2' do
        expect(g.mul_ct(2)).to eq(g.mul(2))
      end

      it 'produces the same result as mul for a large scalar' do
        k = 0xDEADBEEFCAFEBABE
        expect(g.mul_ct(k)).to eq(g.mul(k))
      end

      it 'produces known 2*G coordinates' do
        two_g = g.mul_ct(2)
        expect(two_g.x).to eq(0xC6047F9441ED7D6D3045406E95C07CD85C778E4B8CEF3CA7ABAC09B95C709EE5)
        expect(two_g.y).to eq(0x1AE168FEA63DC339A3C58419466CEAEEF7F632653266D0E1236431A950CFE52A)
      end

      it 'produces known 3*G coordinates' do
        three_g = g.mul_ct(3)
        expect(three_g.x).to eq(0xF9308A019258C31049344F85F89D5229B531C845836F99B08601F113BCE036F9)
        expect(three_g.y).to eq(0x388F7B0F632DE8140FE337E62A37F3566500A99934C2231B6CB9FD7584B8E672)
      end

      it '0 * G = infinity' do
        expect(g.mul_ct(0).infinity?).to be true
      end

      it 'N * G = infinity' do
        expect(g.mul_ct(s::N).infinity?).to be true
      end

      it 'result is on the curve' do
        result = g.mul_ct(0xABCDEF0123456789)
        expect(result.on_curve?).to be true
      end

      it 'matches wNAF for the secp256k1 generator with scalar N-1' do
        # This tests the edge case of the largest valid scalar
        k = s::N - 1
        ct = g.mul_ct(k)
        vt = g.mul(k)
        expect(ct).to eq(vt)
      end
    end

    describe '#add' do
      let(:g) { described_class.generator }

      it 'G + infinity = G' do
        expect(g.add(described_class.infinity)).to eq(g)
      end

      it 'infinity + G = G' do
        expect(described_class.infinity.add(g)).to eq(g)
      end

      it 'G + (-G) = infinity' do
        neg_g = g.negate
        expect(g.add(neg_g).infinity?).to be true
      end

      it 'is commutative' do
        two_g = g.mul(2)
        three_g = g.mul(3)
        expect(two_g.add(three_g)).to eq(three_g.add(two_g))
      end

      it '(k*G) + (m*G) = (k+m)*G' do
        k = 12_345
        m = 67_890
        expect(g.mul(k).add(g.mul(m))).to eq(g.mul(k + m))
      end
    end

    describe '#negate' do
      let(:g) { described_class.generator }

      it 'negation has same x, negated y' do
        neg = g.negate
        expect(neg.x).to eq(g.x)
        expect(neg.y).to eq(s::P - g.y)
      end

      it 'infinity negation is infinity' do
        expect(described_class.infinity.negate.infinity?).to be true
      end
    end

    describe '#==' do
      let(:g) { described_class.generator }

      it 'equal points are ==' do
        expect(g).to eq(described_class.new(s::GX, s::GY))
      end

      it 'different points are not ==' do
        expect(g).not_to eq(g.mul(2))
      end

      it 'two infinity points are equal' do
        first  = described_class.infinity
        second = described_class.infinity
        expect(first).to eq(second)
      end

      it 'infinity != non-infinity' do
        expect(described_class.infinity).not_to eq(g)
      end
    end
  end
end
