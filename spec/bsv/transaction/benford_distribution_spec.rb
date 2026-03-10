# frozen_string_literal: true

# Statistical validation of the Benford-inspired change distribution.
#
# These specs verify the statistical properties of the `benford_number` helper
# and `distribute_random_change` method. They use large sample sizes to avoid
# flakiness and test against known mathematical expectations.
#
# ## How `benford_number` works
#
# `benford_number(min, max, rng)` picks digit d uniformly from 1..9 and
# returns:
#
#   floor(min + (max - min) * log10(1 + 1/d))
#
# This produces exactly 9 possible output values, one per digit. Because
# log10(1 + 1/d) is a decreasing function of d, smaller d values produce
# larger outputs — but d itself is chosen uniformly, so the 9 outputs each
# occur with probability ~1/9.
#
# The "Benford" property is in the *scaling*: the sizes of the 9 outputs are
# proportional to Benford's probability formula, not that the output leading
# digits follow Benford's distribution.
#
# ## What these tests validate
#
# 1. Chi-squared uniformity test on d selection (9 output values, each ~1/9).
# 2. Bias towards lower values: the majority of outputs fall below the range
#    midpoint, because smaller d → larger output, but the d=1 output (the
#    largest) still sits well below (max - min).
# 3. `distribute_random_change` sum invariant over 1000 samples.
# 4. All change outputs receive >= 1 satoshi over 1000 samples.
# 5. Variance is non-zero across repeated distributions.

# Chi-squared critical value for df=8 at p=0.01 significance level.
# We use df=8 because there are 9 output values (9 - 1 = 8 degrees of freedom).
BENFORD_CHI_SQUARED_CRITICAL_P01 = 20.09

RSpec.describe 'Benford change distribution — statistical validation' do # rubocop:disable RSpec/DescribeClass
  # Expose the private helper via a thin wrapper so we can test it directly.
  let(:tx_class) { BSV::Transaction::Transaction }

  def benford_number(min, max, rng)
    priv_tx = tx_class.allocate
    priv_tx.send(:benford_number, min, max, rng)
  end

  # Compute a chi-squared statistic.
  #
  # @param observed [Array<Integer>] observed counts per bucket
  # @param expected_counts [Array<Float>] expected counts per bucket
  # @return [Float]
  def chi_squared(observed, expected_counts)
    observed.zip(expected_counts).sum do |obs, exp|
      ((obs - exp)**2) / exp
    end
  end

  describe 'benford_number output distribution' do
    let(:sample_size) { 18_000 } # divisible by 9 for clean expected counts
    let(:range_min)   { 0 }
    let(:range_max)   { 1_000_000 }

    # Compute the 9 distinct output values this function can produce.
    let(:possible_outputs) do
      (1..9).map do |d|
        (range_min + ((range_max - range_min) * Math.log10(1 + (1.0 / d)))).floor
      end
    end

    it 'produces exactly the 9 expected distinct values' do
      rng = Random.new(42)
      actual_values = Array.new(sample_size) { benford_number(range_min, range_max, rng) }
      unique_values = actual_values.uniq.sort
      expect(unique_values).to eq(possible_outputs.uniq.sort)
    end

    it 'selects d uniformly — each of the 9 outputs appears ~1/9 of the time (chi-squared p > 0.01)' do
      # Since d is chosen uniformly from 1..9, each output value should occur
      # with frequency 1/9. A chi-squared test against equal expected counts
      # verifies this.
      expected_count = sample_size / 9.0

      [42, 137, 999, 271_828, 314_159].each do |seed|
        rng = Random.new(seed)
        counts = Hash.new(0)
        sample_size.times { counts[benford_number(range_min, range_max, rng)] += 1 }

        observed = possible_outputs.map { |v| counts[v] }
        expected = Array.new(9, expected_count)

        chi2 = chi_squared(observed, expected)
        expect(chi2).to be < BENFORD_CHI_SQUARED_CRITICAL_P01,
                        "Chi-squared #{chi2.round(2)} >= #{BENFORD_CHI_SQUARED_CRITICAL_P01} " \
                        "for seed #{seed} (digit d is not uniformly distributed)"
      end
    end

    it 'biases towards lower end of range — majority of outputs below midpoint' do
      # Each output value is below the midpoint because log10(1 + 1/d) < 0.5 for all d in 1..9:
      #   max scaling factor (d=1): log10(2) ≈ 0.301 < 0.5
      # Therefore ALL outputs of benford_number(0, max) are below max/2.
      rng = Random.new(42)
      midpoint = (range_max - range_min) / 2
      values = Array.new(10_000) { benford_number(range_min, range_max, rng) }
      below_mid = values.count { |v| v < midpoint }

      # Every possible output is below midpoint (log10(2) ≈ 0.301), so 100% expected.
      expect(below_mid).to eq(10_000),
                           "Expected all values below midpoint #{midpoint}; " \
                           "got #{10_000 - below_mid} above"
    end

    it 'returns values within [min, max) for multiple seeds' do
      [1, 7, 42, 100, 999].each do |seed|
        rng = Random.new(seed)
        1_000.times do
          n = benford_number(range_min, range_max, rng)
          expect(n).to be >= range_min
          expect(n).to be < range_max
        end
      end
    end

    it 'smaller d values produce larger outputs (Benford scaling)' do
      # The 9 outputs should be strictly decreasing as d increases 1..9,
      # because log10(1 + 1/d) is strictly decreasing.
      expect(possible_outputs).to eq(possible_outputs.sort.reverse)
    end
  end

  describe 'distribute_random_change integration' do
    let(:priv) { BSV::Primitives::PrivateKey.generate }
    let(:lock_script) { BSV::Script::Script.p2pkh_lock(priv.public_key.hash160) }

    def build_tx(input_sats:, output_sats:, change_count:)
      tx = tx_class.new
      input = BSV::Transaction::TransactionInput.new(
        prev_tx_id: BSV::Primitives::Digest.sha256d('test'),
        prev_tx_out_index: 0
      )
      input.source_satoshis = input_sats
      input.source_locking_script = lock_script
      input.unlocking_script_template = BSV::Transaction::P2PKH.new(priv)
      tx.add_input(input)

      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: output_sats,
                      locking_script: lock_script
                    ))

      change_count.times do
        tx.add_output(BSV::Transaction::TransactionOutput.new(
                        satoshis: 0,
                        locking_script: lock_script,
                        change: true
                      ))
      end

      tx
    end

    it 'sum of all outputs equals total inputs minus fee across 1000 samples' do
      input_sats   = 100_000
      output_sats  = 10_000
      fee_sats     = 1_000
      change_count = 3
      expected_total = input_sats - fee_sats

      1_000.times do |i|
        rng = Random.new(i)
        tx = build_tx(input_sats: input_sats, output_sats: output_sats, change_count: change_count)
        tx.fee(fee_sats, change_distribution: :random, rng: rng)
        total = tx.outputs.sum(&:satoshis)
        expect(total).to eq(expected_total), "Seed #{i}: expected #{expected_total}, got #{total}"
      end
    end

    it 'all change outputs receive >= 1 satoshi across 1000 samples' do
      input_sats   = 100_000
      output_sats  = 10_000
      fee_sats     = 1_000
      change_count = 4

      1_000.times do |i|
        rng = Random.new(i)
        tx = build_tx(input_sats: input_sats, output_sats: output_sats, change_count: change_count)
        tx.fee(fee_sats, change_distribution: :random, rng: rng)

        tx.outputs.select(&:change).each_with_index do |output, j|
          expect(output.satoshis).to be >= 1,
                                     "Seed #{i}, change output #{j}: got #{output.satoshis} sats"
        end
      end
    end

    it 'produces meaningfully varied change amounts (non-zero variance)' do
      # Run 1000 distributions and collect the first change output's amount.
      # If the distribution were always equal, every sample would be the same.
      first_change_amounts = Array.new(1_000) do |i|
        rng = Random.new(i)
        tx = build_tx(input_sats: 100_000, output_sats: 10_000, change_count: 3)
        tx.fee(1_000, change_distribution: :random, rng: rng)
        tx.outputs.select(&:change).first.satoshis
      end

      unique_values = first_change_amounts.uniq
      expect(unique_values.length).to be > 1,
                                      'Expected varied change amounts but all samples were identical'

      mean = first_change_amounts.sum.to_f / first_change_amounts.length
      variance = first_change_amounts.sum { |v| (v - mean)**2 } / first_change_amounts.length
      expect(variance).to be > 0, 'Variance of change amounts should be > 0'
    end
  end
end
