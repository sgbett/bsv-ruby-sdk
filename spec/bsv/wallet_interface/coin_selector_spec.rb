# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::CoinSelector do
  # Default fee model: 1 sat/kB. At this rate every transaction is well below the
  # 1000-byte threshold, so fees are always 1 sat unless a higher rate is used.
  let(:fee_model) { BSV::Wallet::FeeModel.new(sats_per_kb: 1) }
  let(:selector)  { described_class.new(fee_model: fee_model) }

  # Convenience helper to build a minimal UTXO hash.
  def utxo(satoshis, txid: 'deadbeef', vout: 0)
    { satoshis: satoshis, outpoint: { txid: txid, vout: vout } }
  end

  describe '#initialize' do
    it 'accepts :standard strategy' do
      expect { described_class.new(fee_model: fee_model, strategy: :standard) }.not_to raise_error
    end

    it 'accepts :largest_first strategy' do
      expect { described_class.new(fee_model: fee_model, strategy: :largest_first) }.not_to raise_error
    end

    it 'raises ArgumentError for an unknown strategy' do
      expect { described_class.new(fee_model: fee_model, strategy: :unknown) }
        .to raise_error(ArgumentError, /unknown strategy/)
    end
  end

  describe '#select' do
    context 'when the pool is empty' do
      it 'raises InsufficientFundsError' do
        expect { selector.select(available: [], target_satoshis: 500, num_outputs: 1) }
          .to raise_error(BSV::Wallet::InsufficientFundsError)
      end
    end

    context 'when the pool cannot cover target + fees' do
      it 'raises InsufficientFundsError' do
        pool = [utxo(100), utxo(200)]
        expect { selector.select(available: pool, target_satoshis: 500, num_outputs: 1) }
          .to raise_error(BSV::Wallet::InsufficientFundsError)
      end

      it 'reports available and required satoshis on the error' do
        pool = [utxo(100)]
        error = nil
        begin
          selector.select(available: pool, target_satoshis: 500, num_outputs: 1)
        rescue BSV::Wallet::InsufficientFundsError => e
          error = e
        end
        expect(error.available).to eq(100)
        expect(error.required).to eq(500)
      end
    end

    # ── Standard strategy ─────────────────────────────────────────────────────

    context 'with :standard strategy — exact match' do
      # Pool [501, 1000, 5000], target 500, 1 output.
      # fee for 1in/1out = 1 sat → need exactly 501.
      # 501-sat UTXO is a perfect fit; no change needed.
      let(:pool) { [utxo(501, txid: 'aa'), utxo(1000, txid: 'bb'), utxo(5000, txid: 'cc')] }

      it 'selects the 501-sat UTXO' do
        result = selector.select(available: pool, target_satoshis: 500, num_outputs: 1)
        expect(result[:inputs].map { |u| u[:satoshis] }).to eq([501])
      end

      it 'returns fee of 1' do
        result = selector.select(available: pool, target_satoshis: 500, num_outputs: 1)
        expect(result[:fee]).to eq(1)
      end

      it 'returns excess of 0' do
        result = selector.select(available: pool, target_satoshis: 500, num_outputs: 1)
        expect(result[:excess]).to eq(0)
      end
    end

    context 'with :standard strategy — smallest sufficient' do
      # Pool [100, 300, 700, 2000], target 500, 1 output.
      # fee for 1in/1out = 1 sat → need ≥ 501.
      # Candidates: 700, 2000. Smallest is 700.
      let(:pool) { [utxo(100), utxo(300), utxo(700), utxo(2000)] }

      it 'selects the 700-sat UTXO' do
        result = selector.select(available: pool, target_satoshis: 500, num_outputs: 1)
        expect(result[:inputs].map { |u| u[:satoshis] }).to eq([700])
      end

      it 'returns correct excess' do
        result = selector.select(available: pool, target_satoshis: 500, num_outputs: 1)
        # 700 - 500 - 1 = 199
        expect(result[:excess]).to eq(199)
      end
    end

    context 'with :standard strategy — accumulation when no single UTXO is sufficient' do
      # Pool [100, 200, 300], target 500.
      # No single UTXO is ≥ 501.
      # Largest-first: 300 → 200 → 100. Total = 600.
      # fee for 3in/2out (1 recipient + 1 change) at 1 sat/kB = 1 sat.
      let(:pool) { [utxo(100), utxo(200), utxo(300)] }

      it 'accumulates all three UTXOs' do
        result = selector.select(available: pool, target_satoshis: 500, num_outputs: 1)
        expect(result[:inputs].map { |u| u[:satoshis] }.sort).to eq([100, 200, 300])
      end

      it 'returns total_satoshis of 600' do
        result = selector.select(available: pool, target_satoshis: 500, num_outputs: 1)
        expect(result[:total_satoshis]).to eq(600)
      end

      it 'recalculates fee for the accumulated input count' do
        result = selector.select(available: pool, target_satoshis: 500, num_outputs: 1)
        # 3 inputs, 2 outputs (1 recipient + 1 change) at 1 sat/kB → 1 sat
        expect(result[:fee]).to eq(1)
      end
    end

    context 'with :standard strategy — fee convergence' do
      # Pool [1000], target 999, 1 output.
      # fee = 1 sat → need 1000. Pool has exactly 1000. Excess = 0.
      let(:pool) { [utxo(1000)] }

      it 'selects the 1000-sat UTXO' do
        result = selector.select(available: pool, target_satoshis: 999, num_outputs: 1)
        expect(result[:inputs].map { |u| u[:satoshis] }).to eq([1000])
      end

      it 'returns excess of 0' do
        result = selector.select(available: pool, target_satoshis: 999, num_outputs: 1)
        expect(result[:excess]).to eq(0)
      end
    end

    context 'with :standard strategy — zero target satoshis' do
      # Only need enough to cover the fee (~1 sat). Pool has 100.
      let(:pool) { [utxo(100)] }

      it 'selects a UTXO to cover fees' do
        result = selector.select(available: pool, target_satoshis: 0, num_outputs: 1)
        expect(result[:inputs]).not_to be_empty
      end

      it 'returns a non-negative excess below the UTXO value' do
        result = selector.select(available: pool, target_satoshis: 0, num_outputs: 1)
        expect(result[:excess]).to be >= 0
        expect(result[:excess]).to be < 100
      end
    end

    context 'with :standard strategy — multiple outputs affect fee' do
      # Pool [1000], target 100, 5 outputs.
      # fee for 1in/5out at 1 sat/kB:
      #   size = 10 + 148 + 5×34 = 328 bytes → ceil(0.328) = 1 sat
      let(:pool) { [utxo(1000)] }

      it 'selects the 1000-sat UTXO' do
        result = selector.select(available: pool, target_satoshis: 100, num_outputs: 5)
        expect(result[:inputs].map { |u| u[:satoshis] }).to eq([1000])
      end

      it 'fee reflects the correct output count' do
        result = selector.select(available: pool, target_satoshis: 100, num_outputs: 5)
        expected_fee = fee_model.estimate(p2pkh_inputs: 1, p2pkh_outputs: 5)
        expect(result[:fee]).to eq(expected_fee)
      end
    end

    # ── Largest-first strategy ────────────────────────────────────────────────

    context 'with :largest_first strategy' do
      let(:selector) { described_class.new(fee_model: fee_model, strategy: :largest_first) }

      # Pool [100, 500, 300], target 200.
      # Largest-first: 500 is tried first. fee for 1in/2out at 1 sat/kB = 1 sat.
      # 500 ≥ 200 + 1 = 201 → done.
      it 'picks the 500-sat UTXO without considering smaller ones' do
        pool   = [utxo(100), utxo(500), utxo(300)]
        result = selector.select(available: pool, target_satoshis: 200, num_outputs: 1)
        expect(result[:inputs].map { |u| u[:satoshis] }).to eq([500])
      end

      it 'returns correct excess when largest UTXO is selected' do
        pool   = [utxo(100), utxo(500), utxo(300)]
        result = selector.select(available: pool, target_satoshis: 200, num_outputs: 1)
        fee    = fee_model.estimate(p2pkh_inputs: 1, p2pkh_outputs: 2)
        expect(result[:excess]).to eq(500 - 200 - fee)
      end

      it 'raises InsufficientFundsError when the pool is insufficient' do
        pool = [utxo(50)]
        expect { selector.select(available: pool, target_satoshis: 500, num_outputs: 1) }
          .to raise_error(BSV::Wallet::InsufficientFundsError)
      end
    end

    # ── Result structure invariants ───────────────────────────────────────────

    describe 'result structure' do
      it 'returns a hash with :inputs, :fee, :total_satoshis, and :excess keys' do
        pool   = [utxo(1000)]
        result = selector.select(available: pool, target_satoshis: 500, num_outputs: 1)
        expect(result).to include(:inputs, :fee, :total_satoshis, :excess)
      end

      it ':excess is never negative' do
        pool   = [utxo(1000)]
        result = selector.select(available: pool, target_satoshis: 999, num_outputs: 1)
        expect(result[:excess]).to be >= 0
      end

      it ':total_satoshis equals the sum of selected input satoshis' do
        pool   = [utxo(300), utxo(400)]
        result = selector.select(available: pool, target_satoshis: 600, num_outputs: 1)
        expect(result[:total_satoshis]).to eq(result[:inputs].sum { |u| u[:satoshis] })
      end
    end
  end
end
