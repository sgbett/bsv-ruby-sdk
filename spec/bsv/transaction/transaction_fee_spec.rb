# frozen_string_literal: true

RSpec.describe BSV::Transaction::Transaction do
  describe '#fee' do
    let(:priv) { BSV::Primitives::PrivateKey.generate }
    let(:lock_script) { BSV::Script::Script.p2pkh_lock(priv.public_key.hash160) }

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
        tx.fee(1000)

        change_outputs = tx.outputs.select(&:change)
        expect(change_outputs.length).to eq(2)
        expect(change_outputs.sum(&:satoshis)).to eq(49_000)
        # Equal split: 24500 each
        expect(change_outputs[0].satoshis).to eq(24_500)
        expect(change_outputs[1].satoshis).to eq(24_500)
      end

      it 'distributes remainder to first outputs' do
        tx = build_tx(input_sats: 100_000, output_sats: 50_000, change_count: 3)
        tx.fee(1000)

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

    describe 'backwards compatibility' do
      it 'estimated_fee still works' do
        tx = build_tx(input_sats: 100_000, output_sats: 50_000)
        expect(tx.estimated_fee).to be_a(Integer)
        expect(tx.estimated_fee).to be > 0
      end
    end

    describe 'invalid argument' do
      it 'raises ArgumentError for unexpected types' do
        tx = build_tx(input_sats: 100_000, output_sats: 50_000)
        expect { tx.fee('invalid') }.to raise_error(ArgumentError, /expected FeeModel/)
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
