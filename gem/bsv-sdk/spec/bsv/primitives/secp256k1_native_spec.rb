# frozen_string_literal: true

require 'spec_helper'

# Known affine coordinates for small multiples of the secp256k1 generator G.
# Defined outside the describe block to satisfy Lint/ConstantDefinitionInBlock.
SECP256K1_TWO_G_X   = 0xC6047F9441ED7D6D3045406E95C07CD85C778E4B8CEF3CA7ABAC09B95C709EE5
SECP256K1_TWO_G_Y   = 0x1AE168FEA63DC339A3C58419466CEAEEF7F632653266D0E1236431A950CFE52A
SECP256K1_THREE_G_X = 0xF9308A019258C31049344F85F89D5229B531C845836F99B08601F113BCE036F9
SECP256K1_THREE_G_Y = 0x388F7B0F632DE8140FE337E62A37F3566500A99934C2231B6CB9FD7584B8E672
SECP256K1_FIVE_G_X  = 0x2F8BDE4D1A07209355B4A7250A5C5128E88B84BDDC619AB7CBA8D569B240EFE4
SECP256K1_FIVE_G_Y  = 0xD8AC222636E5E3D6D4DBA9DDA6C9C426F788271BAB0D6840DCA87D3AA6AC62D6

RSpec.describe 'BSV::Primitives::Secp256k1Native' do
  # The native extension is only available when compiled. Skip gracefully if
  # the .bundle/.so has not been built yet.
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    require 'bsv/secp256k1_native'
  rescue LoadError
    skip 'Native extension not compiled — run `bundle exec rake compile` first'
  end

  let(:n)   { BSV::Primitives::Secp256k1Native }
  let(:ref) { BSV::Primitives::Secp256k1 }
  let(:p)   { BSV::Primitives::Secp256k1::P }
  let(:gx)  { BSV::Primitives::Secp256k1::GX }
  let(:gy)  { BSV::Primitives::Secp256k1::GY }

  describe 'module structure' do
    it 'is defined as a Module' do
      expect(BSV::Primitives::Secp256k1Native).to be_a(Module)
    end

    it 'is nested under BSV::Primitives' do
      expect(BSV::Primitives.const_defined?(:Secp256k1Native)).to be true
    end
  end

  describe 'BSV::Primitives::Secp256k1 (regression after extension load)' do
    it 'still computes fmul correctly' do
      expect(ref.fmul(2, 3)).to eq(6)
    end

    it 'still computes field inverse correctly' do
      a = p - 1
      expect(ref.fmul(a, ref.finv(a))).to eq(1)
    end

    it 'still multiplies the generator point correctly' do
      g = BSV::Primitives::Secp256k1::Point.generator
      result = g.mul(2)
      expect(result.on_curve?).to be true
      expect(result.x).to eq(
        0xC6047F9441ED7D6D3045406E95C07CD85C778E4B8CEF3CA7ABAC09B95C709EE5
      )
    end
  end

  describe '#fred' do
    it 'returns 0 for input 0' do
      expect(n.fred(0)).to eq(0)
    end

    it 'returns 0 for input P' do
      expect(n.fred(p)).to eq(0)
    end

    it 'returns P-1 for input P-1' do
      expect(n.fred(p - 1)).to eq(p - 1)
    end

    it 'reduces P*P to 0' do
      expect(n.fred(p * p)).to eq(0)
    end

    it 'matches the Ruby reference for a large intermediate value' do
      val = gx * gy
      expect(n.fred(val)).to eq(ref.fred(val))
    end

    it 'raises ArgumentError for negative input' do
      expect { n.fred(-1) }.to raise_error(ArgumentError)
    end
  end

  describe '#fmul' do
    it 'returns 0 when either operand is 0' do
      expect(n.fmul(0, gx)).to eq(0)
      expect(n.fmul(gx, 0)).to eq(0)
    end

    it 'is the identity when one operand is 1' do
      expect(n.fmul(1, gx)).to eq(gx)
      expect(n.fmul(gx, 1)).to eq(gx)
    end

    it 'returns 1 for (P-1) * (P-1) mod P' do
      # (P-1)^2 = P^2 - 2P + 1 ≡ 1 (mod P)
      expect(n.fmul(p - 1, p - 1)).to eq(1)
    end

    it 'matches the Ruby reference for GX * GY' do
      expect(n.fmul(gx, gy)).to eq(ref.fmul(gx, gy))
    end

    it 'is commutative' do
      a = gx
      b = gy
      expect(n.fmul(a, b)).to eq(n.fmul(b, a))
    end
  end

  describe '#fsqr' do
    it 'returns 0 for input 0' do
      expect(n.fsqr(0)).to eq(0)
    end

    it 'returns 1 for input 1' do
      expect(n.fsqr(1)).to eq(1)
    end

    it 'returns 1 for input P-1' do
      # (P-1)^2 ≡ 1 (mod P)
      expect(n.fsqr(p - 1)).to eq(1)
    end

    it 'matches fmul(a,a) for the generator x-coordinate' do
      expect(n.fsqr(gx)).to eq(n.fmul(gx, gx))
    end

    it 'matches the Ruby reference' do
      expect(n.fsqr(gx)).to eq(ref.fsqr(gx))
    end
  end

  describe '#fadd' do
    it 'wraps correctly at P-1 + 1' do
      expect(n.fadd(p - 1, 1)).to eq(0)
    end

    it 'returns P-2 for (P-1) + (P-1)' do
      # (P-1) + (P-1) = 2P - 2 ≡ P - 2 (mod P)
      expect(n.fadd(p - 1, p - 1)).to eq(p - 2)
    end

    it 'returns 0 for 0 + 0' do
      expect(n.fadd(0, 0)).to eq(0)
    end

    it 'matches the Ruby reference for GX + GY' do
      expect(n.fadd(gx, gy)).to eq(ref.fadd(gx, gy))
    end

    it 'is commutative' do
      expect(n.fadd(gx, gy)).to eq(n.fadd(gy, gx))
    end
  end

  describe '#fsub' do
    it 'returns P-1 for 0 - 1' do
      expect(n.fsub(0, 1)).to eq(p - 1)
    end

    it 'returns 0 for a - a' do
      expect(n.fsub(gx, gx)).to eq(0)
    end

    it 'returns 0 for 0 - 0' do
      expect(n.fsub(0, 0)).to eq(0)
    end

    it 'wraps correctly when a < b' do
      # 1 - (P-1) = 1 - P + 1 ≡ 2 (mod P)
      expect(n.fsub(1, p - 1)).to eq(2)
    end

    it 'matches the Ruby reference' do
      expect(n.fsub(gx, gy)).to eq(ref.fsub(gx, gy))
    end
  end

  describe '#fneg' do
    it 'returns 0 for input 0 (branchless zero handling)' do
      expect(n.fneg(0)).to eq(0)
    end

    it 'returns P-1 for input 1' do
      expect(n.fneg(1)).to eq(p - 1)
    end

    it 'returns 1 for input P-1' do
      expect(n.fneg(p - 1)).to eq(1)
    end

    it 'negation is its own inverse' do
      expect(n.fneg(n.fneg(gx))).to eq(gx)
    end

    it 'matches the Ruby reference' do
      expect(n.fneg(gx)).to eq(ref.fneg(gx))
    end

    it 'satisfies a + neg(a) = 0' do
      expect(n.fadd(gx, n.fneg(gx))).to eq(0)
    end
  end

  describe '#finv' do
    it 'raises ArgumentError for zero input' do
      expect { n.finv(0) }.to raise_error(ArgumentError, /zero/)
    end

    it 'returns 1 for input 1' do
      expect(n.finv(1)).to eq(1)
    end

    it 'satisfies a * inv(a) = 1' do
      expect(n.fmul(gx, n.finv(gx))).to eq(1)
    end

    it 'satisfies a * inv(a) = 1 for P-1' do
      expect(n.fmul(p - 1, n.finv(p - 1))).to eq(1)
    end

    it 'matches the Ruby reference' do
      expect(n.finv(gx)).to eq(ref.finv(gx))
    end

    it 'matches the Ruby reference for GY' do
      expect(n.finv(gy)).to eq(ref.finv(gy))
    end
  end

  describe '#fsqrt' do
    it 'returns 0 for input 0' do
      expect(n.fsqrt(0)).to eq(0)
    end

    it 'returns 1 for input 1' do
      expect(n.fsqrt(1)).to eq(1)
    end

    it 'returns nil for 3 (not a quadratic residue mod P)' do
      expect(n.fsqrt(3)).to be_nil
    end

    it 'returns a valid root for GX^3 + 7 (the secp256k1 y^2 at x = GX)' do
      y_squared = ref.fadd(ref.fmul(ref.fsqr(gx), gx), 7)
      root = n.fsqrt(y_squared)
      expect(root).not_to be_nil
      expect(n.fmul(root, root)).to eq(y_squared)
    end

    it 'satisfies sqrt(a)^2 == a for quadratic residues' do
      # Any field element squared is a QR
      a = n.fsqr(gx)
      root = n.fsqrt(a)
      expect(root).not_to be_nil
      expect(n.fmul(root, root)).to eq(a)
    end

    it 'matches the Ruby reference result or its negation' do
      y_squared = ref.fadd(ref.fmul(ref.fsqr(gx), gx), 7)
      c_root = n.fsqrt(y_squared)
      ruby_root = ref.fsqrt(y_squared)
      # Both roots ±r are valid; match one of them
      expect([c_root, p - c_root]).to include(ruby_root)
    end
  end

  describe '#scalar_mod' do
    let(:curve_n) { BSV::Primitives::Secp256k1::N }

    it 'returns 0 for input 0' do
      expect(n.scalar_mod(0)).to eq(0)
    end

    it 'returns 0 for input N' do
      expect(n.scalar_mod(curve_n)).to eq(0)
    end

    it 'returns N-1 for input -1' do
      expect(n.scalar_mod(-1)).to eq(curve_n - 1)
    end

    it 'returns 0 for input -N' do
      expect(n.scalar_mod(-curve_n)).to eq(0)
    end

    it 'returns 1 for input N+1' do
      expect(n.scalar_mod(curve_n + 1)).to eq(1)
    end

    it 'matches the Ruby reference for a typical value' do
      expect(n.scalar_mod(gx)).to eq(ref.scalar_mod(gx))
    end
  end

  describe '#scalar_mul' do
    let(:curve_n) { BSV::Primitives::Secp256k1::N }

    it 'returns 0 when either operand is 0' do
      expect(n.scalar_mul(0, gx)).to eq(0)
      expect(n.scalar_mul(gx, 0)).to eq(0)
    end

    it 'returns 1 for (N-1) * (N-1) mod N' do
      # (N-1)^2 = N^2 - 2N + 1 ≡ 1 (mod N)
      expect(n.scalar_mul(curve_n - 1, curve_n - 1)).to eq(1)
    end

    it 'is the identity when one operand is 1' do
      expect(n.scalar_mul(1, gx % curve_n)).to eq(gx % curve_n)
    end

    it 'is commutative' do
      a = gx % curve_n
      b = gy % curve_n
      expect(n.scalar_mul(a, b)).to eq(n.scalar_mul(b, a))
    end

    it 'matches the Ruby reference' do
      a = gx % curve_n
      b = gy % curve_n
      expect(n.scalar_mul(a, b)).to eq(ref.scalar_mul(a, b))
    end
  end

  describe '#scalar_inv' do
    let(:curve_n) { BSV::Primitives::Secp256k1::N }

    it 'raises ArgumentError for zero input' do
      expect { n.scalar_inv(0) }.to raise_error(ArgumentError, /zero/)
    end

    it 'returns 1 for input 1' do
      expect(n.scalar_inv(1)).to eq(1)
    end

    it 'satisfies a * inv(a) ≡ 1 (mod N)' do
      a = gx % curve_n
      expect(n.scalar_mul(a, n.scalar_inv(a))).to eq(1)
    end

    it 'satisfies (N-1) * inv(N-1) ≡ 1 (mod N)' do
      a = curve_n - 1
      expect(n.scalar_mul(a, n.scalar_inv(a))).to eq(1)
    end

    it 'matches the Ruby reference' do
      a = gx % curve_n
      expect(n.scalar_inv(a)).to eq(ref.scalar_inv(a))
    end
  end

  describe '#scalar_add' do
    let(:curve_n) { BSV::Primitives::Secp256k1::N }

    it 'returns 1 for (N-1) + 2' do
      expect(n.scalar_add(curve_n - 1, 2)).to eq(1)
    end

    it 'returns 0 for (N-1) + 1' do
      expect(n.scalar_add(curve_n - 1, 1)).to eq(0)
    end

    it 'returns 0 for 0 + 0' do
      expect(n.scalar_add(0, 0)).to eq(0)
    end

    it 'is commutative' do
      a = gx % curve_n
      b = gy % curve_n
      expect(n.scalar_add(a, b)).to eq(n.scalar_add(b, a))
    end

    it 'matches the Ruby reference' do
      a = gx % curve_n
      b = gy % curve_n
      expect(n.scalar_add(a, b)).to eq(ref.scalar_add(a, b))
    end
  end

  describe 'cross-validation: 100 random pairs vs Ruby reference' do
    it 'produces identical results for all field operations' do
      failures = []
      rng = Random.new(0x5EED) # local RNG — does not contaminate global seed
      100.times do |i|
        a = rng.rand(p)
        b = rng.rand(p)

        { fmul: [a, b], fadd: [a, b], fsub: [a, b] }.each do |op, args|
          got      = n.send(op, *args)
          expected = ref.send(op, *args)
          if got != expected
            failures << "iter #{i}: #{op}(#{a.to_s(16)[0, 8]}..., #{b.to_s(16)[0, 8]}...): " \
                        "got #{got.to_s(16)[0, 8]}, expected #{expected.to_s(16)[0, 8]}"
          end
        end

        { fsqr: a, fneg: a, finv: a }.each do |op, arg|
          got      = n.send(op, arg)
          expected = ref.send(op, arg)
          if got != expected
            failures << "iter #{i}: #{op}(#{arg.to_s(16)[0, 8]}...): " \
                        "got #{got.to_s(16)[0, 8]}, expected #{expected.to_s(16)[0, 8]}"
          end
        end
      end

      expect(failures).to be_empty, failures.first(5).join("\n")
    end

    it 'produces identical results for all scalar operations' do
      curve_n = BSV::Primitives::Secp256k1::N
      failures = []
      rng = Random.new(0xABCDEF) # local RNG — does not contaminate global seed
      100.times do |i|
        a = rng.rand(curve_n)
        b = rng.rand(curve_n)

        { scalar_mul: [a, b], scalar_add: [a, b] }.each do |op, args|
          got      = n.send(op, *args)
          expected = ref.send(op, *args)
          if got != expected
            failures << "iter #{i}: #{op}(#{a.to_s(16)[0, 8]}..., #{b.to_s(16)[0, 8]}...): " \
                        "got #{got.to_s(16)[0, 8]}, expected #{expected.to_s(16)[0, 8]}"
          end
        end

        next if a.zero?

        got      = n.scalar_inv(a)
        expected = ref.scalar_inv(a)
        if got != expected
          failures << "iter #{i}: scalar_inv(#{a.to_s(16)[0, 8]}...): " \
                      "got #{got.to_s(16)[0, 8]}, expected #{expected.to_s(16)[0, 8]}"
        end
      end

      expect(failures).to be_empty, failures.first(5).join("\n")
    end
  end

  # ---------------------------------------------------------------------------
  # Jacobian point operations
  # ---------------------------------------------------------------------------

  # Jacobian representation of G (affine with Z=1).
  def g_jacobian
    [BSV::Primitives::Secp256k1::GX, BSV::Primitives::Secp256k1::GY, 1]
  end

  # The Jacobian point at infinity [0, 1, 0].
  def jp_infinity
    [0, 1, 0]
  end

  # Convert a Jacobian point to affine using the Ruby implementation.
  def to_affine(jac_pt)
    BSV::Primitives::Secp256k1.jp_to_affine(jac_pt)
  end

  describe '#jp_double' do
    it 'doubles G to produce the correct affine 2G coordinates' do
      result = n.jp_double(g_jacobian)
      affine = to_affine(result)
      expect(affine[0]).to eq(SECP256K1_TWO_G_X)
      expect(affine[1]).to eq(SECP256K1_TWO_G_Y)
    end

    it 'returns infinity when doubling infinity (Z of result is zero)' do
      result = n.jp_double(jp_infinity)
      expect(result[2]).to eq(0)
    end

    it 'matches the Ruby reference implementation for G' do
      ref_result = ref.jp_double(g_jacobian)
      c_result   = n.jp_double(g_jacobian)
      expect(to_affine(c_result)).to eq(to_affine(ref_result))
    end

    it 'matches Ruby reference when doubling a non-trivial Jacobian point (2G → 4G)' do
      two_g_jac  = ref.jp_double(g_jacobian)
      ref_result = ref.jp_double(two_g_jac)
      c_result   = n.jp_double(two_g_jac)
      expect(to_affine(c_result)).to eq(to_affine(ref_result))
    end
  end

  describe '#jp_add' do
    it 'returns q when p is infinity' do
      result = n.jp_add(jp_infinity, g_jacobian)
      expect(to_affine(result)).to eq([gx, gy])
    end

    it 'returns p when q is infinity' do
      result = n.jp_add(g_jacobian, jp_infinity)
      expect(to_affine(result)).to eq([gx, gy])
    end

    it 'adding two infinities returns infinity' do
      result = n.jp_add(jp_infinity, jp_infinity)
      expect(result[2]).to eq(0)
    end

    it 'adds G + G to produce 2G' do
      result = n.jp_add(g_jacobian, g_jacobian)
      affine = to_affine(result)
      expect(affine[0]).to eq(SECP256K1_TWO_G_X)
      expect(affine[1]).to eq(SECP256K1_TWO_G_Y)
    end

    it 'jp_add(G, G) equals jp_double(G) in affine coordinates' do
      double_result = n.jp_double(g_jacobian)
      add_result    = n.jp_add(g_jacobian, g_jacobian)
      expect(to_affine(add_result)).to eq(to_affine(double_result))
    end

    it 'adds 2G + 3G to produce 5G' do
      two_g_jac   = ref.jp_double(g_jacobian)
      three_g_jac = ref.jp_add(two_g_jac, g_jacobian)
      result      = n.jp_add(two_g_jac, three_g_jac)
      affine      = to_affine(result)
      expect(affine[0]).to eq(SECP256K1_FIVE_G_X)
      expect(affine[1]).to eq(SECP256K1_FIVE_G_Y)
    end

    it 'returns infinity when adding a point to its negation' do
      neg_g  = n.jp_neg(g_jacobian)
      result = n.jp_add(g_jacobian, neg_g)
      expect(result[2]).to eq(0)
    end

    it 'matches the Ruby reference for G + 2G = 3G' do
      two_g_jac  = ref.jp_double(g_jacobian)
      ref_result = ref.jp_add(g_jacobian, two_g_jac)
      c_result   = n.jp_add(g_jacobian, two_g_jac)
      expect(to_affine(c_result)).to eq(to_affine(ref_result))
    end
  end

  describe '#jp_neg' do
    it 'negates G: result is [GX, P-GY, 1]' do
      result = n.jp_neg(g_jacobian)
      expect(result[0]).to eq(gx)
      expect(result[1]).to eq(p - gy)
      expect(result[2]).to eq(1)
    end

    it 'negates infinity: Z remains zero' do
      result = n.jp_neg(jp_infinity)
      expect(result[2]).to eq(0)
    end

    it 'double negation returns the original affine point' do
      neg_g     = n.jp_neg(g_jacobian)
      neg_neg_g = n.jp_neg(neg_g)
      expect(to_affine(neg_neg_g)).to eq([gx, gy])
    end

    it 'matches the Ruby reference' do
      expect(n.jp_neg(g_jacobian)).to eq(ref.jp_neg(g_jacobian))
    end
  end

  describe 'Jacobian cross-validation: scalar multiply results via C point ops' do
    # For each scalar k, verify that the Ruby scalar multiply (which delegates
    # to jp_double/jp_add — C versions after native loading) produces the
    # same affine point as the known pure-Ruby wNAF result.
    [1, 2, 3, 7, 0xDEADBEEF].each do |k|
      it "k=#{k}: scalar multiply produces correct affine point" do
        ruby_jac = BSV::Primitives::Secp256k1.scalar_multiply_wnaf(k, gx, gy)
        affine   = BSV::Primitives::Secp256k1.jp_to_affine(ruby_jac)
        g        = BSV::Primitives::Secp256k1::Point.generator
        result   = g.mul(k)
        expect(result.on_curve?).to be true
        expect(result.x).to eq(affine[0])
        expect(result.y).to eq(affine[1])
      end
    end
  end

  # ---------------------------------------------------------------------------
  # scalar_multiply_ct — constant-time Montgomery ladder
  # ---------------------------------------------------------------------------

  describe '#scalar_multiply_ct' do
    let(:curve_n) { BSV::Primitives::Secp256k1::N }

    it 'k=1 returns the base point (identity)' do
      result = n.scalar_multiply_ct(1, gx, gy)
      affine = to_affine(result)
      expect(affine[0]).to eq(gx)
      expect(affine[1]).to eq(gy)
    end

    it 'k=2 returns 2G (known coordinates)' do
      result = n.scalar_multiply_ct(2, gx, gy)
      affine = to_affine(result)
      expect(affine[0]).to eq(SECP256K1_TWO_G_X)
      expect(affine[1]).to eq(SECP256K1_TWO_G_Y)
    end

    it 'k=3 returns 3G (known coordinates)' do
      result = n.scalar_multiply_ct(3, gx, gy)
      affine = to_affine(result)
      expect(affine[0]).to eq(SECP256K1_THREE_G_X)
      expect(affine[1]).to eq(SECP256K1_THREE_G_Y)
    end

    it 'k=N-1 returns -G (negation of the base point)' do
      # -G has the same x-coordinate as G but negated y (i.e. P - GY)
      result = n.scalar_multiply_ct(curve_n - 1, gx, gy)
      affine = to_affine(result)
      expect(affine[0]).to eq(gx)
      expect(affine[1]).to eq(p - gy)
    end

    it 'k=0 returns the point at infinity [0, 1, 0]' do
      result = n.scalar_multiply_ct(0, gx, gy)
      expect(result).to eq([0, 1, 0])
    end

    it 'k=N raises ArgumentError' do
      expect { n.scalar_multiply_ct(curve_n, gx, gy) }.to raise_error(ArgumentError)
    end

    it 'k negative raises ArgumentError' do
      expect { n.scalar_multiply_ct(-1, gx, gy) }.to raise_error(ArgumentError)
    end

    it 'matches the Ruby reference for k=7' do
      ref_jac = ref.scalar_multiply_ct(7, gx, gy)
      c_result = n.scalar_multiply_ct(7, gx, gy)
      expect(to_affine(c_result)).to eq(to_affine(ref_jac))
    end

    it 'matches the Ruby reference for k=0xDEADBEEF' do
      k = 0xDEADBEEF
      ref_jac  = ref.scalar_multiply_ct(k, gx, gy)
      c_result = n.scalar_multiply_ct(k, gx, gy)
      expect(to_affine(c_result)).to eq(to_affine(ref_jac))
    end

    it 'matches Point.generator.mul for 50 random scalars' do
      rng = Random.new(0xC0FFEE)
      failures = []
      g = BSV::Primitives::Secp256k1::Point.generator
      50.times do |i|
        k = 1 + rng.rand(curve_n - 1)
        c_result  = n.scalar_multiply_ct(k, gx, gy)
        c_affine  = to_affine(c_result)
        ruby_pt   = g.mul(k)
        failures << "iter #{i}: k=#{k.to_s(16)[0, 8]}... x mismatch" \
          if c_affine[0] != ruby_pt.x || c_affine[1] != ruby_pt.y
      end
      expect(failures).to be_empty, failures.first(3).join("\n")
    end
  end

  # ---------------------------------------------------------------------------
  # Native delegation: verify Secp256k1 module delegates to C implementations
  # ---------------------------------------------------------------------------

  describe 'BSV::Primitives::Secp256k1 native delegation' do
    # When the native extension is loaded, all delegated methods should report
    # nil source_location — the hallmark of a C-implemented method (or a Proc
    # wrapping one that has no Ruby source).
    delegated_methods = %i[
      fmul fsqr fadd fsub fneg finv fsqrt fred
      scalar_mod scalar_mul scalar_inv scalar_add
      jp_double jp_add jp_neg scalar_multiply_ct
    ]

    delegated_methods.each do |m|
      it "#{m} is delegated to the native extension (nil source_location)" do
        expect(BSV::Primitives::Secp256k1.method(m).source_location).to be_nil
      end
    end

    it 'native delegation does not break scalar multiply via wNAF' do
      g      = BSV::Primitives::Secp256k1::Point.generator
      result = g.mul(5)
      expect(result.on_curve?).to be true
      expect(result.x).to eq(SECP256K1_FIVE_G_X)
      expect(result.y).to eq(SECP256K1_FIVE_G_Y)
    end

    it 'native delegation does not break constant-time scalar multiply' do
      g      = BSV::Primitives::Secp256k1::Point.generator
      result = g.mul_ct(3)
      expect(result.on_curve?).to be true
      expect(result.x).to eq(SECP256K1_THREE_G_X)
      expect(result.y).to eq(SECP256K1_THREE_G_Y)
    end
  end
end
