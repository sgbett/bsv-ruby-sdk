# frozen_string_literal: true

RSpec.describe BSV::Transaction::Transaction do
  describe '#fee' do
    let(:priv) { BSV::Primitives::PrivateKey.generate }
    let(:lock_script) { BSV::Script::Script.p2pkh_lock(priv.public_key.hash160) }

    def seed_rng(seed)
      rng = Random.new(seed)
      allow(Random).to(receive(:rand).and_wrap_original { |_m, *args| rng.rand(*args) })
    end

    def build_tx(input_sats:, output_sats:, change_sats: 0, change_count: 1)
      tx = described_class.new
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
                        satoshis: change_sats,
                        locking_script: lock_script,
                        change: true
                      ))
      end

      tx
    end

    describe 'with default fee model' do
      it 'computes fee and adjusts change output' do
        tx = build_tx(input_sats: 100_000, output_sats: 50_000)
        tx.fee

        change_outputs = tx.outputs.select(&:change)
        expect(change_outputs.length).to eq(1)
        expect(change_outputs[0].satoshis).to be > 0

        total_out = tx.outputs.sum(&:satoshis)
        expect(total_out).to be < 100_000 # fee deducted
      end
    end

    describe 'with SatoshisPerKilobyte model' do
      it 'computes fee at custom rate' do
        tx = build_tx(input_sats: 100_000, output_sats: 50_000)
        model = BSV::Transaction::FeeModels::SatoshisPerKilobyte.new(value: 100)
        tx.fee(model)

        change_outputs = tx.outputs.select(&:change)
        expect(change_outputs.length).to eq(1)
        expect(change_outputs[0].satoshis).to be > 0
      end
    end

    describe 'with fixed numeric fee' do
      it 'uses the exact fee amount' do
        tx = build_tx(input_sats: 100_000, output_sats: 50_000)
        tx.fee(1000)

        change_outputs = tx.outputs.select(&:change)
        expect(change_outputs.length).to eq(1)
        expect(change_outputs[0].satoshis).to eq(49_000)
      end
    end

    describe 'change distribution' do
      it 'distributes change across multiple change outputs equally' do
        tx = build_tx(input_sats: 100_000, output_sats: 50_000, change_count: 2)
        tx.fee(1000, change_distribution: :equal)

        change_outputs = tx.outputs.select(&:change)
        expect(change_outputs.length).to eq(2)
        expect(change_outputs.sum(&:satoshis)).to eq(49_000)
        # Equal split: 24500 each
        expect(change_outputs[0].satoshis).to eq(24_500)
        expect(change_outputs[1].satoshis).to eq(24_500)
      end

      it 'distributes remainder to first outputs' do
        tx = build_tx(input_sats: 100_000, output_sats: 50_000, change_count: 3)
        tx.fee(1000, change_distribution: :equal)

        change_outputs = tx.outputs.select(&:change)
        expect(change_outputs.length).to eq(3)
        total = change_outputs.sum(&:satoshis)
        expect(total).to eq(49_000)
        # 49000 / 3 = 16333 remainder 1
        expect(change_outputs[0].satoshis).to eq(16_334)
        expect(change_outputs[1].satoshis).to eq(16_333)
        expect(change_outputs[2].satoshis).to eq(16_333)
      end

      it 'removes change outputs when insufficient change' do
        tx = build_tx(input_sats: 51_000, output_sats: 50_000)
        tx.fee(1000)

        # 51000 - 50000 - 1000 = 0, which is <= 1 change output
        expect(tx.outputs.select(&:change)).to be_empty
        expect(tx.outputs.length).to eq(1)
      end

      it 'removes change outputs when change is negative (overspend to miners)' do
        tx = build_tx(input_sats: 50_500, output_sats: 50_000)
        tx.fee(1000)

        # 50500 - 50000 - 1000 = -500, remove change outputs
        expect(tx.outputs.select(&:change)).to be_empty
      end
    end

    describe 'no change outputs' do
      it 'works without change outputs' do
        tx = described_class.new
        input = BSV::Transaction::TransactionInput.new(
          prev_tx_id: BSV::Primitives::Digest.sha256d('test'),
          prev_tx_out_index: 0
        )
        input.source_satoshis = 100_000
        input.source_locking_script = lock_script
        input.unlocking_script_template = BSV::Transaction::P2PKH.new(priv)
        tx.add_input(input)
        tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 99_000, locking_script: lock_script))

        expect { tx.fee(1000) }.not_to raise_error
        expect(tx.outputs.length).to eq(1)
        expect(tx.outputs[0].satoshis).to eq(99_000)
      end
    end

    describe 'returns self for chaining' do
      it 'returns the transaction' do
        tx = build_tx(input_sats: 100_000, output_sats: 50_000)
        expect(tx.fee(1000)).to eq(tx)
      end
    end

    describe 'estimated_fee deprecation (F4.2)' do
      before { described_class.instance_variable_set(:@_estimated_fee_warned, false) }

      it 'still works and returns an integer' do
        tx = build_tx(input_sats: 100_000, output_sats: 50_000)
        expect(tx.estimated_fee).to be_a(Integer)
        expect(tx.estimated_fee).to be > 0
      end

      it 'delegates through SatoshisPerKilobyte — both paths agree' do
        tx = build_tx(input_sats: 100_000, output_sats: 50_000)
        model = BSV::Transaction::FeeModels::SatoshisPerKilobyte.new
        expect(tx.estimated_fee).to eq(model.compute_fee(tx))
      end

      it 'respects explicit satoshis_per_byte and delegates correctly' do
        tx = build_tx(input_sats: 100_000, output_sats: 50_000)
        model = BSV::Transaction::FeeModels::SatoshisPerKilobyte.new(value: 500)
        expect(tx.estimated_fee(satoshis_per_byte: 0.5)).to eq(model.compute_fee(tx))
      end

      it 'emits a deprecation warning' do
        tx = build_tx(input_sats: 100_000, output_sats: 50_000)
        expect { tx.estimated_fee }.to output(/DEPRECATION.*estimated_fee/).to_stderr
      end

      it 'emits the warning only once per process' do
        tx = build_tx(input_sats: 100_000, output_sats: 50_000)
        expect { tx.estimated_fee }.to output(/DEPRECATION/).to_stderr
        expect { tx.estimated_fee }.not_to output.to_stderr
      end
    end

    describe 'invalid argument' do
      it 'raises ArgumentError for unexpected types' do
        tx = build_tx(input_sats: 100_000, output_sats: 50_000)
        expect { tx.fee('invalid') }.to raise_error(ArgumentError, /expected FeeModel/)
      end

      it 'raises ArgumentError for invalid change_distribution' do
        tx = build_tx(input_sats: 100_000, output_sats: 50_000)
        expect { tx.fee(1000, change_distribution: :banana) }
          .to raise_error(ArgumentError, /invalid change_distribution/)
      end
    end

    it 'defaults to :equal distribution' do
      # No change_distribution: argument — should behave identically to :equal
      tx = build_tx(input_sats: 100_000, output_sats: 50_000, change_count: 2)
      tx.fee(1000)

      change_outputs = tx.outputs.select(&:change)
      expect(change_outputs.length).to eq(2)
      expect(change_outputs[0].satoshis).to eq(24_500)
      expect(change_outputs[1].satoshis).to eq(24_500)
    end

    describe 'random change distribution' do
      it 'single change output receives the full available amount' do
        tx = build_tx(input_sats: 100_000, output_sats: 50_000)
        tx.fee(1000, change_distribution: :random)

        change_outputs = tx.outputs.select(&:change)
        expect(change_outputs.length).to eq(1)
        expect(change_outputs[0].satoshis).to eq(49_000)
      end

      it 'preserves total satoshis exactly — no satoshis lost or created' do
        seed_rng(42)
        tx = build_tx(input_sats: 100_000, output_sats: 50_000, change_count: 3)
        tx.fee(1000, change_distribution: :random)

        # Total of all outputs (including non-change) must equal inputs minus fee
        total = tx.outputs.sum(&:satoshis)
        expect(total).to eq(99_000) # 100_000 - 1_000
      end

      it 'allocates at least 1 satoshi to each change output' do
        seed_rng(42)
        tx = build_tx(input_sats: 100_000, output_sats: 50_000, change_count: 4)
        tx.fee(1000, change_distribution: :random)

        change_outputs = tx.outputs.select(&:change)
        change_outputs.each do |output|
          expect(output.satoshis).to be >= 1
        end
      end

      it 'produces varied amounts with multiple change outputs (stubbed RNG)' do
        seed_rng(12_345)
        tx = build_tx(input_sats: 1_000_000, output_sats: 100_000, change_count: 3)
        tx.fee(1000, change_distribution: :random)

        change_outputs = tx.outputs.select(&:change)
        amounts = change_outputs.map(&:satoshis)
        # With a seeded RNG and multiple outputs, amounts should not all be equal
        expect(amounts.uniq.length).to be > 1
      end

      it 'assigns any floor-rounding remainder to the last transaction output' do
        # Use a tiny pool where rounding will definitely produce a remainder.
        # For d in 1..9, benford_number(0, 2) = floor(2 * log10(1 + 1/d))
        # d=1: floor(2 * log10(2)) = floor(0.602) = 0; remainder sent to last tx output.
        # We verify the sum invariant: all sats accounted for.
        seed_rng(99)
        tx = build_tx(input_sats: 60_000, output_sats: 50_000, change_count: 3)
        tx.fee(1000, change_distribution: :random)

        total = tx.outputs.sum(&:satoshis)
        expect(total).to eq(59_000) # 60_000 - 1_000
      end

      it 'is deterministic with the same seeded RNG' do
        seed_rng(7)
        tx1 = build_tx(input_sats: 500_000, output_sats: 100_000, change_count: 3)
        tx1.fee(1000, change_distribution: :random)

        seed_rng(7)
        tx2 = build_tx(input_sats: 500_000, output_sats: 100_000, change_count: 3)
        tx2.fee(1000, change_distribution: :random)

        amounts1 = tx1.outputs.select(&:change).map(&:satoshis)
        amounts2 = tx2.outputs.select(&:change).map(&:satoshis)
        expect(amounts1).to eq(amounts2)
      end

      it 'removes change outputs when available is zero' do
        # F4.1: change outputs are now only removed when available <= 0.
        # available = 51000 - 50000 - 1000 = 0 → remove change outputs
        tx = build_tx(input_sats: 51_000, output_sats: 50_000, change_count: 2)
        tx.fee(1000, change_distribution: :random)
        expect(tx.outputs.select(&:change)).to be_empty
      end

      it 'handles two change outputs (single iteration plus remainder)' do
        seed_rng(1)
        tx = build_tx(input_sats: 100_000, output_sats: 50_000, change_count: 2)
        tx.fee(1000, change_distribution: :random)

        change_outputs = tx.outputs.select(&:change)
        expect(change_outputs.length).to eq(2)
        # Sum of all outputs must equal inputs minus fee
        expect(tx.outputs.sum(&:satoshis)).to eq(99_000)
      end

      it 'handles very large change amounts without integer overflow' do
        # 100 BTC = 10_000_000_000 sats — Ruby handles big integers natively
        seed_rng(3)
        large_input = 10_000_000_000
        fee_sats = 1000
        tx = build_tx(input_sats: large_input, output_sats: 1_000_000, change_count: 3)
        tx.fee(fee_sats, change_distribution: :random)

        total = tx.outputs.sum(&:satoshis)
        expect(total).to eq(large_input - fee_sats)
      end
    end
  end

  describe BSV::Transaction::TransactionOutput do
    describe '#change' do
      it 'defaults to false' do
        output = described_class.new(
          satoshis: 1000,
          locking_script: BSV::Script::Script.from_asm('OP_TRUE')
        )
        expect(output.change).to be false
      end

      it 'can be set to true' do
        output = described_class.new(
          satoshis: 1000,
          locking_script: BSV::Script::Script.from_asm('OP_TRUE'),
          change: true
        )
        expect(output.change).to be true
      end
    end
  end
end
