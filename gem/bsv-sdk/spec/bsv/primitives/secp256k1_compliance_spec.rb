# frozen_string_literal: true

require 'spec_helper'

# Known affine coordinates for small multiples of the secp256k1 generator G.
# Computed from the secp256k1 generator using standard EC point arithmetic,
# independently verifiable against published test vectors.
# Defined outside the describe block to satisfy Lint/ConstantDefinitionInBlock.
COMPLIANCE_2G_X  = 0xC6047F9441ED7D6D3045406E95C07CD85C778E4B8CEF3CA7ABAC09B95C709EE5
COMPLIANCE_2G_Y  = 0x1AE168FEA63DC339A3C58419466CEAEEF7F632653266D0E1236431A950CFE52A
COMPLIANCE_3G_X  = 0xF9308A019258C31049344F85F89D5229B531C845836F99B08601F113BCE036F9
COMPLIANCE_3G_Y  = 0x388F7B0F632DE8140FE337E62A37F3566500A99934C2231B6CB9FD7584B8E672
COMPLIANCE_4G_X  = 0xE493DBF1C10D80F3581E4904930B1404CC6C13900EE0758474FA94ABE8C4CD13
COMPLIANCE_4G_Y  = 0x51ED993EA0D455B75642E2098EA51448D967AE33BFBDFE40CFE97BDC47739922
COMPLIANCE_5G_X  = 0x2F8BDE4D1A07209355B4A7250A5C5128E88B84BDDC619AB7CBA8D569B240EFE4
COMPLIANCE_5G_Y  = 0xD8AC222636E5E3D6D4DBA9DDA6C9C426F788271BAB0D6840DCA87D3AA6AC62D6
COMPLIANCE_6G_X  = 0xFFF97BD5755EEEA420453A14355235D382F6472F8568A18B2F057A1460297556
COMPLIANCE_6G_Y  = 0xAE12777AACFBB620F3BE96017F45C560DE80F0F6518FE4A03C870C36B075F297
COMPLIANCE_7G_X  = 0x5CBDF0646E5DB4EAA398F365F2EA7A0E3D419B7E0330E39CE92BDDEDCAC4F9BC
COMPLIANCE_7G_Y  = 0x6AEBCA40BA255960A3178D6D861A54DBA813D0B813FDE7B5A5082628087264DA

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'secp256k1 compliance' do
  # rubocop:enable RSpec/DescribeClass
  let(:s) { BSV::Primitives::Secp256k1 }
  let(:p) { BSV::Primitives::Secp256k1::P }
  let(:n) { BSV::Primitives::Secp256k1::N }

  # ---------------------------------------------------------------------------
  # Shared examples: field arithmetic
  # ---------------------------------------------------------------------------
  shared_examples 'secp256k1 field arithmetic' do |mod|
    let(:field) { mod }
    let(:fp) { mod::P }

    context 'identity laws' do
      it 'fmul(1, x) == x' do
        x = 0xDEADBEEF1234567890ABCDEF
        expect(field.fmul(1, x)).to eq(x)
      end

      it 'fadd(0, x) == x' do
        x = 0xDEADBEEF1234567890ABCDEF
        expect(field.fadd(0, x)).to eq(x)
      end

      it 'fsub(x, 0) == x' do
        x = 0xDEADBEEF1234567890ABCDEF
        expect(field.fsub(x, 0)).to eq(x)
      end
    end

    context 'boundary values' do
      it 'fmul(P-1, P-1) == 1' do
        # (P-1)^2 = P^2 - 2P + 1 ≡ 1 (mod P)
        expect(field.fmul(fp - 1, fp - 1)).to eq(1)
      end

      it 'fadd(P-1, 1) == 0' do
        expect(field.fadd(fp - 1, 1)).to eq(0)
      end

      it 'fsub(0, 1) == P-1' do
        expect(field.fsub(0, 1)).to eq(fp - 1)
      end
    end

    context 'zero laws' do
      it 'fmul(0, x) == 0' do
        x = 0xDEADBEEF
        expect(field.fmul(0, x)).to eq(0)
      end

      it 'fneg(0) == 0' do
        expect(field.fneg(0)).to eq(0)
      end

      it 'fsqrt(0) == 0' do
        expect(field.fsqrt(0)).to eq(0)
      end
    end

    context 'inverse' do
      it 'finv(1) == 1' do
        expect(field.finv(1)).to eq(1)
      end

      it 'finv(0) raises ArgumentError' do
        expect { field.finv(0) }.to raise_error(ArgumentError)
      end
    end

    context 'square root' do
      it 'fsqrt(1) == 1' do
        expect(field.fsqrt(1)).to eq(1)
      end

      it 'fsqrt(non-residue) == nil (3 is not a QR mod P)' do
        expect(field.fsqrt(3)).to be_nil
      end
    end

    context 'double negation' do
      it 'fneg(fneg(x)) == x' do
        x = 0xABCDEF01234567890
        expect(field.fneg(field.fneg(x))).to eq(x % fp)
      end
    end

    context 'associativity' do
      it 'fmul(a, fmul(b, c)) == fmul(fmul(a, b), c)' do
        a = 0x1234567890ABCDEF
        b = 0xFEDCBA0987654321
        c = 0xDEADBEEFCAFEBABE
        lhs = field.fmul(a, field.fmul(b, c))
        rhs = field.fmul(field.fmul(a, b), c)
        expect(lhs).to eq(rhs)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Shared examples: scalar arithmetic
  # ---------------------------------------------------------------------------
  shared_examples 'secp256k1 scalar arithmetic' do |mod|
    let(:scalar) { mod }
    let(:curve_n) { mod::N }

    context 'scalar_mod boundary values' do
      it 'scalar_mod(N) == 0' do
        expect(scalar.scalar_mod(curve_n)).to eq(0)
      end

      it 'scalar_mod(-1) == N-1' do
        expect(scalar.scalar_mod(-1)).to eq(curve_n - 1)
      end

      it 'scalar_mod(0) == 0' do
        expect(scalar.scalar_mod(0)).to eq(0)
      end
    end

    context 'scalar_mul' do
      it 'scalar_mul(N-1, N-1) == 1' do
        # (N-1)^2 = N^2 - 2N + 1 ≡ 1 (mod N)
        expect(scalar.scalar_mul(curve_n - 1, curve_n - 1)).to eq(1)
      end

      it 'scalar_mul(1, x) == x' do
        x = 0xDEADBEEF % curve_n
        expect(scalar.scalar_mul(1, x)).to eq(x)
      end

      it 'scalar_mul(0, x) == 0' do
        x = 0xDEADBEEF % curve_n
        expect(scalar.scalar_mul(0, x)).to eq(0)
      end
    end

    context 'scalar_inv' do
      it 'scalar_inv(1) == 1' do
        expect(scalar.scalar_inv(1)).to eq(1)
      end

      it 'scalar_inv(0) raises ArgumentError' do
        expect { scalar.scalar_inv(0) }.to raise_error(ArgumentError)
      end
    end

    context 'scalar_add' do
      it 'scalar_add(N-1, 1) == 0' do
        expect(scalar.scalar_add(curve_n - 1, 1)).to eq(0)
      end

      it 'scalar_add(0, 0) == 0' do
        expect(scalar.scalar_add(0, 0)).to eq(0)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Shared examples: point operations
  # ---------------------------------------------------------------------------
  shared_examples 'secp256k1 point operations' do
    let(:pt) { BSV::Primitives::Secp256k1::Point }
    let(:s)  { BSV::Primitives::Secp256k1 }
    let(:fp) { BSV::Primitives::Secp256k1::P }
    let(:g)  { pt.generator }

    context 'known multiples of G' do
      [
        [2, COMPLIANCE_2G_X, COMPLIANCE_2G_Y],
        [3, COMPLIANCE_3G_X, COMPLIANCE_3G_Y],
        [4, COMPLIANCE_4G_X, COMPLIANCE_4G_Y],
        [5, COMPLIANCE_5G_X, COMPLIANCE_5G_Y],
        [6, COMPLIANCE_6G_X, COMPLIANCE_6G_Y],
        [7, COMPLIANCE_7G_X, COMPLIANCE_7G_Y]
      ].each do |k, expected_x, expected_y|
        it "#{k}G has correct affine coordinates" do
          result = g.mul(k)
          expect(result.x).to eq(expected_x), "#{k}G x mismatch: got 0x#{result.x.to_s(16).upcase}"
          expect(result.y).to eq(expected_y), "#{k}G y mismatch: got 0x#{result.y.to_s(16).upcase}"
        end
      end

      it '(N-1)G has x == GX and y == P - GY' do
        curve_n = BSV::Primitives::Secp256k1::N
        result = g.mul(curve_n - 1)
        expect(result.x).to eq(BSV::Primitives::Secp256k1::GX)
        expect(result.y).to eq(fp - BSV::Primitives::Secp256k1::GY)
      end
    end

    context 'on-curve checks' do
      [2, 3, 4, 5, 6, 7].each do |k|
        it "#{k}G is on the curve" do
          expect(g.mul(k).on_curve?).to be true
        end
      end
    end

    context 'infinity handling' do
      it '0 * G == infinity' do
        expect(g.mul(0).infinity?).to be true
      end

      it 'N * G == infinity' do
        curve_n = BSV::Primitives::Secp256k1::N
        expect(g.mul(curve_n).infinity?).to be true
      end

      it 'G + (-G) == infinity' do
        expect(g.add(g.negate).infinity?).to be true
      end

      it 'infinity + G == G' do
        expect(pt.infinity.add(g)).to eq(g)
      end

      it 'G + infinity == G' do
        expect(g.add(pt.infinity)).to eq(g)
      end

      it 'double(infinity) == infinity' do
        inf = pt.infinity
        expect(inf.add(inf).infinity?).to be true
      end
    end

    context 'mul_ct matches mul for known multiples' do
      [1, 2, 3, 5, 7].each do |k|
        it "mul_ct(#{k}) == mul(#{k})" do
          expect(g.mul_ct(k)).to eq(g.mul(k))
        end
      end

      it 'mul_ct(N-1) == mul(N-1)' do
        curve_n = BSV::Primitives::Secp256k1::N
        expect(g.mul_ct(curve_n - 1)).to eq(g.mul(curve_n - 1))
      end
    end

    context 'compressed round-trip for non-trivial points' do
      [2, 3, 7].each do |k|
        it "#{k}G compressed round-trip" do
          original = g.mul(k)
          serialised = original.to_octet_string(:compressed)
          recovered = pt.from_bytes(serialised)
          expect(recovered).to eq(original)
        end

        it "#{k}G uncompressed round-trip" do
          original = g.mul(k)
          serialised = original.to_octet_string(:uncompressed)
          recovered = pt.from_bytes(serialised)
          expect(recovered).to eq(original)
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-validation: 200 deterministic random pairs
  #
  # Uses a frozen local RNG (Random.new(seed)) to avoid contaminating the global
  # seed. Tests all field and scalar operations against the reference module.
  # After native extension loading, Secp256k1 delegates to C; before loading it
  # uses pure Ruby. Either way the results must agree.
  # ---------------------------------------------------------------------------
  shared_examples 'secp256k1 cross-validation' do |mod|
    let(:ref)     { mod }
    let(:fp)      { mod::P }
    let(:curve_n) { mod::N }

    it 'field operations produce identical results for 200 random pairs' do
      failures = []
      rng = Random.new(0xC0FFEE)
      200.times do |i|
        a = rng.rand(fp)
        b = rng.rand(fp)
        next if a.zero? || b.zero?

        { fmul: [a, b], fadd: [a, b], fsub: [a, b] }.each do |op, args|
          got      = ref.send(op, *args)
          expected = (a.send({ fmul: :*, fadd: :+, fsub: :- }[op], b) % fp)
          next if got == expected

          failures << "iter #{i}: #{op}(#{a.to_s(16)[0, 8]}..., #{b.to_s(16)[0, 8]}...): " \
                      "got #{got.to_s(16)[0, 8]}, expected #{expected.to_s(16)[0, 8]}"
        end

        { fsqr: a, fneg: a, finv: a }.each do |op, arg|
          expected = case op
                     when :fsqr then (arg * arg) % fp
                     when :fneg then arg.zero? ? 0 : fp - arg
                     when :finv then arg.pow(fp - 2, fp)
                     end
          got = ref.send(op, arg)
          next if got == expected

          failures << "iter #{i}: #{op}(#{arg.to_s(16)[0, 8]}...): " \
                      "got #{got.to_s(16)[0, 8]}, expected #{expected.to_s(16)[0, 8]}"
        end
      end

      expect(failures).to be_empty, failures.first(5).join("\n")
    end

    it 'scalar operations produce identical results for 200 random pairs' do
      failures = []
      rng = Random.new(0xC0FFEE_BEEF)
      200.times do |i|
        a = rng.rand(curve_n)
        b = rng.rand(curve_n)
        next if a.zero? || b.zero?

        { scalar_mul: [a, b], scalar_add: [a, b] }.each do |op, args|
          got      = ref.send(op, *args)
          expected = (a.send({ scalar_mul: :*, scalar_add: :+ }[op], b) % curve_n)
          next if got == expected

          failures << "iter #{i}: #{op}(#{a.to_s(16)[0, 8]}..., #{b.to_s(16)[0, 8]}...): " \
                      "got #{got.to_s(16)[0, 8]}, expected #{expected.to_s(16)[0, 8]}"
        end

        got      = ref.scalar_inv(a)
        expected = a.pow(curve_n - 2, curve_n)
        next if got == expected

        failures << "iter #{i}: scalar_inv(#{a.to_s(16)[0, 8]}...): " \
                    "got #{got.to_s(16)[0, 8]}, expected #{expected.to_s(16)[0, 8]}"
      end

      expect(failures).to be_empty, failures.first(5).join("\n")
    end
  end

  # ---------------------------------------------------------------------------
  # Exercise the shared examples through BSV::Primitives::Secp256k1
  #
  # NOTE: RSpec loads files alphabetically. `secp256k1_compliance_spec.rb`
  # sorts before `secp256k1_native_spec.rb`. When the native spec loads it
  # calls `require 'bsv/secp256k1_native'`, which patches Secp256k1's methods
  # to delegate to C. In a combined run the second describe block below runs
  # after native loading; when running this file alone, both blocks exercise
  # pure Ruby. Either way correctness is validated.
  # ---------------------------------------------------------------------------

  describe 'Secp256k1 (pure Ruby)' do
    it_behaves_like 'secp256k1 field arithmetic', BSV::Primitives::Secp256k1
    it_behaves_like 'secp256k1 scalar arithmetic', BSV::Primitives::Secp256k1
    it_behaves_like 'secp256k1 point operations'
    it_behaves_like 'secp256k1 cross-validation', BSV::Primitives::Secp256k1
  end

  # After native extension loading Secp256k1's field/scalar/Jacobian methods
  # delegate to C implementations. The same shared examples must continue to
  # pass through that delegation layer.
  describe 'Secp256k1 (after native extension loading)', if: defined?(BSV::Primitives::Secp256k1Native) do
    before(:all) do # rubocop:disable RSpec/BeforeAfterAll
      require 'bsv/secp256k1_native'
    rescue LoadError
      skip 'Native extension not compiled — run `bundle exec rake compile` first'
    end

    it_behaves_like 'secp256k1 field arithmetic', BSV::Primitives::Secp256k1
    it_behaves_like 'secp256k1 scalar arithmetic', BSV::Primitives::Secp256k1
    it_behaves_like 'secp256k1 point operations'
    it_behaves_like 'secp256k1 cross-validation', BSV::Primitives::Secp256k1
  end
end
