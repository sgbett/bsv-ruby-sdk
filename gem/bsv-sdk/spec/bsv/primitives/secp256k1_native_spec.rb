# frozen_string_literal: true

require 'spec_helper'

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

  describe 'cross-validation: 100 random pairs vs Ruby reference' do
    it 'produces identical results for all field operations' do
      failures = []
      srand(0x5EED) # deterministic seed for reproducibility
      100.times do |i|
        a = rand(p)
        b = rand(p)

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
  end
end
