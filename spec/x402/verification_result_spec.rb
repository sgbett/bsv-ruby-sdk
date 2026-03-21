# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe 'BSV::X402::VerificationResult' do
  describe '.success' do
    subject(:result) { BSV::X402::VerificationResult.success }

    it 'is frozen' do
      expect(result).to be_frozen
    end

    it '#success? returns true' do
      expect(result.success?).to be(true)
    end

    it '#failure? returns false' do
      expect(result.failure?).to be(false)
    end

    it '#step is nil' do
      expect(result.step).to be_nil
    end

    it '#reason is nil' do
      expect(result.reason).to be_nil
    end

    it '#http_status returns 200' do
      expect(result.http_status).to eq(200)
    end
  end

  describe '.failure' do
    subject(:result) { BSV::X402::VerificationResult.failure(step: 3, reason: 'challenge hash mismatch') }

    it 'is frozen' do
      expect(result).to be_frozen
    end

    it '#success? returns false' do
      expect(result.success?).to be(false)
    end

    it '#failure? returns true' do
      expect(result.failure?).to be(true)
    end

    it '#step returns the given step' do
      expect(result.step).to eq(3)
    end

    it '#reason returns the given reason' do
      expect(result.reason).to eq('challenge hash mismatch')
    end
  end

  describe '#http_status' do
    context 'when success' do
      it 'returns 200' do
        expect(BSV::X402::VerificationResult.success.http_status).to eq(200)
      end
    end

    context 'when step 1 (malformed proof structure)' do
      it 'returns 400' do
        expect(BSV::X402::VerificationResult.failure(step: 1, reason: 'x').http_status).to eq(400)
      end
    end

    context 'when step 2 (wrong version or scheme)' do
      it 'returns 400' do
        expect(BSV::X402::VerificationResult.failure(step: 2, reason: 'x').http_status).to eq(400)
      end
    end

    context 'when step 3 (challenge sha256 mismatch)' do
      it 'returns 402' do
        expect(BSV::X402::VerificationResult.failure(step: 3, reason: 'x').http_status).to eq(402)
      end
    end

    context 'when step 4 (request binding mismatch)' do
      it 'returns 400' do
        expect(BSV::X402::VerificationResult.failure(step: 4, reason: 'x').http_status).to eq(400)
      end
    end

    context 'when step 5 (challenge expired)' do
      it 'returns 402' do
        expect(BSV::X402::VerificationResult.failure(step: 5, reason: 'x').http_status).to eq(402)
      end
    end

    context 'when step 6 (bad transaction or txid mismatch)' do
      it 'returns 400' do
        expect(BSV::X402::VerificationResult.failure(step: 6, reason: 'x').http_status).to eq(400)
      end
    end

    context 'when step 7 (nonce UTXO not spent)' do
      it 'returns 402' do
        expect(BSV::X402::VerificationResult.failure(step: 7, reason: 'x').http_status).to eq(402)
      end
    end

    context 'when step 8 (insufficient payment)' do
      it 'returns 402' do
        expect(BSV::X402::VerificationResult.failure(step: 8, reason: 'x').http_status).to eq(402)
      end
    end

    context 'when step 9 (mempool rejection)' do
      it 'returns 402' do
        expect(BSV::X402::VerificationResult.failure(step: 9, reason: 'x').http_status).to eq(402)
      end
    end
  end
end
