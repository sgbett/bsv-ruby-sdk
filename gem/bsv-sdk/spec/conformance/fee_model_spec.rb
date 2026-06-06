# frozen_string_literal: true

require 'spec_helper'

# Protocol conformance: Fee model interface and SatoshisPerKilobyte
#
# Cross-validates the Ruby SDK's fee model against the formula used by all
# three reference SDKs: ceil((size / 1000) * satoshis_per_kb).
#
# Reference implementations:
#   TS SDK:  src/transaction/fee-models/SatoshisPerKilobyte.ts
#   Go SDK:  transaction/fee_model/sats_per_kb.go
#   Python:  fee_models/satoshis_per_kilobyte.py

RSpec.describe BSV::Transaction::FeeModels::SatoshisPerKilobyte do # rubocop:disable RSpec/MultipleDescribes
  describe 'formula conformance: ceil((size / 1000) * rate)' do
    def expected_fee(size_bytes, sat_per_kb)
      (size_bytes / 1000.0 * sat_per_kb).ceil
    end

    [
      { size: 1000, rate: 50, expected: 50, desc: '1 KB at 50 sat/kB' },
      { size: 250,  rate: 50, expected: 13, desc: '250 bytes at 50 sat/kB (rounds up 12.5)' },
      { size: 500,  rate: 100, expected: 50, desc: '500 bytes at 100 sat/kB' },
      { size: 1500, rate: 100, expected: 150, desc: '1.5 KB at 100 sat/kB' },
      { size: 10_000, rate: 50, expected: 500, desc: '10 KB at 50 sat/kB' },
      { size: 1, rate: 1, expected: 1, desc: 'minimum: 1 byte at 1 sat/kB (rounds up 0.001)' },
      { size: 226, rate: 50, expected: 12, desc: 'typical 1-in-1-out P2PKH at 50 sat/kB' },
      { size: 374, rate: 50, expected: 19, desc: 'typical 1-in-2-out P2PKH at 50 sat/kB' }
    ].each do |v|
      it "computes #{v[:expected]} sat for #{v[:desc]}" do
        tx = instance_double(BSV::Transaction::Tx, estimated_size: v[:size])
        model = described_class.new(value: v[:rate])

        fee = model.compute_fee(tx)

        expect(fee).to eq(v[:expected])
        expect(fee).to eq(expected_fee(v[:size], v[:rate]))
      end
    end
  end

  it 'inherits from FeeModel' do
    expect(described_class.superclass).to eq(BSV::Transaction::FeeModel)
  end

  it 'returns an Integer' do
    tx = instance_double(BSV::Transaction::Tx, estimated_size: 250)
    expect(described_class.new.compute_fee(tx)).to be_an(Integer)
  end

  it 'defaults to 100 sat/kB matching reference SDK fallback' do
    expect(described_class.new.value).to eq(100)
  end
end

RSpec.describe BSV::Transaction::Tx do
  describe '#fee conformance' do
    let(:priv) { BSV::Primitives::PrivateKey.generate }
    let(:lock_script) { BSV::Script::Script.p2pkh_lock(priv.public_key.hash160) }

    def build_funded_tx(input_sats:, output_sats:)
      tx = described_class.new
      input = BSV::Transaction::TransactionInput.new(
        prev_wtxid: BSV::Primitives::Digest.sha256d('conformance'),
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
      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: 0,
                      locking_script: lock_script,
                      change: true
                    ))
      tx
    end

    it 'assigns remaining satoshis to change output (matching SDK pattern)' do
      tx = build_funded_tx(input_sats: 100_000, output_sats: 50_000)
      tx.fee(500)

      change = tx.outputs.select(&:change)
      expect(change.length).to eq(1)
      expect(change[0].satoshis).to eq(49_500) # 100000 - 50000 - 500
    end

    it 'removes change outputs when dust (matching SDK pattern)' do
      tx = build_funded_tx(input_sats: 50_100, output_sats: 50_000)
      tx.fee(500)

      expect(tx.outputs.select(&:change)).to be_empty
    end

    it 'accepts nil for default model' do
      tx = build_funded_tx(input_sats: 100_000, output_sats: 50_000)
      tx.fee

      change = tx.outputs.select(&:change)
      expect(change.length).to eq(1)
      expect(change[0].satoshis).to be > 0
    end

    it 'accepts FeeModel instance' do
      tx = build_funded_tx(input_sats: 100_000, output_sats: 50_000)
      model = BSV::Transaction::FeeModels::SatoshisPerKilobyte.new(value: 100)
      tx.fee(model)

      change = tx.outputs.select(&:change)
      expect(change.length).to eq(1)
      expect(change[0].satoshis).to be > 0
    end

    it 'accepts numeric fee (backwards compatibility)' do
      tx = build_funded_tx(input_sats: 100_000, output_sats: 50_000)
      tx.fee(1000)

      change = tx.outputs.select(&:change)
      expect(change[0].satoshis).to eq(49_000)
    end
  end
end
