# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe 'BSV::Wallet::BroadcastQueue' do
  # --------------------------------------------------------------------------
  # Interface enforcement via a dummy adapter
  # --------------------------------------------------------------------------
  let(:dummy_class) do
    Class.new { include BSV::Wallet::BroadcastQueue }
  end
  let(:dummy) { dummy_class.new }

  describe '#enqueue' do
    it 'raises NotImplementedError when not overridden' do
      expect { dummy.enqueue({}) }.to raise_error(NotImplementedError, /enqueue not implemented/)
    end
  end

  describe '#status' do
    it 'raises NotImplementedError when not overridden' do
      expect { dummy.status('abc123') }.to raise_error(NotImplementedError, /status not implemented/)
    end
  end

  describe '#async?' do
    it 'defaults to false' do
      expect(dummy.async?).to be(false)
    end
  end

  # --------------------------------------------------------------------------
  # .status_for_error — error-to-status mapping
  # --------------------------------------------------------------------------
  describe '.status_for_error' do
    subject(:map) { BSV::Wallet::BroadcastQueue.method(:status_for_error) }

    context 'with a non-BroadcastError' do
      it 'returns "serviceError" for a plain StandardError' do
        expect(BSV::Wallet::BroadcastQueue.status_for_error(StandardError.new('boom'))).to eq('serviceError')
      end

      it 'returns "serviceError" for a RuntimeError' do
        expect(BSV::Wallet::BroadcastQueue.status_for_error(RuntimeError.new('oops'))).to eq('serviceError')
      end
    end

    context 'with a BroadcastError' do
      def broadcast_error(arc_status)
        BSV::Network::BroadcastError.new('failed', arc_status: arc_status)
      end

      it 'maps DOUBLE_SPEND_ATTEMPTED to "doubleSpend"' do
        expect(BSV::Wallet::BroadcastQueue.status_for_error(broadcast_error('DOUBLE_SPEND_ATTEMPTED'))).to eq('doubleSpend')
      end

      it 'maps REJECTED to "invalidTx"' do
        expect(BSV::Wallet::BroadcastQueue.status_for_error(broadcast_error('REJECTED'))).to eq('invalidTx')
      end

      it 'maps ORPHAN to "invalidTx"' do
        expect(BSV::Wallet::BroadcastQueue.status_for_error(broadcast_error('ORPHAN'))).to eq('invalidTx')
      end

      it 'maps MIXED_RESULTS_ORPHAN (contains ORPHAN) to "invalidTx"' do
        expect(BSV::Wallet::BroadcastQueue.status_for_error(broadcast_error('MIXED_RESULTS_ORPHAN'))).to eq('invalidTx')
      end

      it 'maps an unrecognised arc_status to "serviceError"' do
        expect(BSV::Wallet::BroadcastQueue.status_for_error(broadcast_error('UNKNOWN_STATUS'))).to eq('serviceError')
      end

      it 'maps nil arc_status to "serviceError"' do
        expect(BSV::Wallet::BroadcastQueue.status_for_error(broadcast_error(nil))).to eq('serviceError')
      end
    end
  end
end
