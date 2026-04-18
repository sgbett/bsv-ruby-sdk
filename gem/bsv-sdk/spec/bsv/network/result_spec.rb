# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Network::Result do
  describe BSV::Network::Result::Success do
    it 'stores data' do
      result = described_class.new(data: 'payload')
      expect(result.data).to eq('payload')
    end

    it 'defaults metadata to empty hash' do
      result = described_class.new(data: nil)
      expect(result.metadata).to eq({})
    end

    it 'stores explicit metadata' do
      result = described_class.new(data: 'x', metadata: { code: 200 })
      expect(result.metadata).to eq({ code: 200 })
    end

    it 'accepts nil data' do
      result = described_class.new(data: nil)
      expect(result.data).to be_nil
    end

    it 'accepts String data' do
      result = described_class.new(data: 'hello')
      expect(result.data).to eq('hello')
    end

    it 'accepts Hash data' do
      result = described_class.new(data: { txid: 'abc' })
      expect(result.data).to eq({ txid: 'abc' })
    end

    it 'accepts Array data' do
      result = described_class.new(data: [1, 2, 3])
      expect(result.data).to eq([1, 2, 3])
    end

    it 'is frozen after construction' do
      result = described_class.new(data: 'x')
      expect(result).to be_frozen
    end

    it 'returns true for success?' do
      expect(described_class.new(data: nil).success?).to be true
    end

    it 'returns false for error?' do
      expect(described_class.new(data: nil).error?).to be false
    end

    it 'returns false for not_found?' do
      expect(described_class.new(data: nil).not_found?).to be false
    end

    describe 'equality' do
      it 'equals another Success with same data and metadata' do
        a = described_class.new(data: 'x', metadata: { k: 1 })
        b = described_class.new(data: 'x', metadata: { k: 1 })
        expect(a).to eq(b)
      end

      it 'does not equal a Success with different data' do
        a = described_class.new(data: 'x')
        b = described_class.new(data: 'y')
        expect(a).not_to eq(b)
      end

      it 'does not equal a Success with different metadata' do
        a = described_class.new(data: 'x', metadata: { k: 1 })
        b = described_class.new(data: 'x', metadata: { k: 2 })
        expect(a).not_to eq(b)
      end

      it 'produces the same hash for equal instances' do
        a = described_class.new(data: 'x')
        b = described_class.new(data: 'x')
        expect(a.hash).to eq(b.hash)
      end
    end
  end

  describe BSV::Network::Result::Error do
    it 'stores message' do
      result = described_class.new(message: 'something failed')
      expect(result.message).to eq('something failed')
    end

    it 'defaults retryable to false' do
      result = described_class.new(message: 'oops')
      expect(result.retryable).to be false
    end

    it 'defaults metadata to empty hash' do
      result = described_class.new(message: 'oops')
      expect(result.metadata).to eq({})
    end

    it 'stores explicit retryable flag' do
      result = described_class.new(message: 'rate limited', retryable: true)
      expect(result.retryable).to be true
    end

    it 'stores explicit metadata' do
      result = described_class.new(message: 'rejected', metadata: { arc_status: 'MINED' })
      expect(result.metadata).to eq({ arc_status: 'MINED' })
    end

    it 'is frozen after construction' do
      result = described_class.new(message: 'fail')
      expect(result).to be_frozen
    end

    it 'returns false for success?' do
      expect(described_class.new(message: 'fail').success?).to be false
    end

    it 'returns true for error?' do
      expect(described_class.new(message: 'fail').error?).to be true
    end

    it 'returns false for not_found?' do
      expect(described_class.new(message: 'fail').not_found?).to be false
    end

    describe '#retryable?' do
      it 'returns false when retryable is false' do
        result = described_class.new(message: 'fail', retryable: false)
        expect(result.retryable?).to be false
      end

      it 'returns true when retryable is true' do
        result = described_class.new(message: 'rate limited', retryable: true)
        expect(result.retryable?).to be true
      end
    end

    describe 'equality' do
      it 'equals another Error with same attributes' do
        a = described_class.new(message: 'fail', retryable: true, metadata: { code: 429 })
        b = described_class.new(message: 'fail', retryable: true, metadata: { code: 429 })
        expect(a).to eq(b)
      end

      it 'does not equal an Error with different message' do
        a = described_class.new(message: 'fail')
        b = described_class.new(message: 'other')
        expect(a).not_to eq(b)
      end

      it 'does not equal an Error with different retryable' do
        a = described_class.new(message: 'fail', retryable: false)
        b = described_class.new(message: 'fail', retryable: true)
        expect(a).not_to eq(b)
      end

      it 'produces the same hash for equal instances' do
        a = described_class.new(message: 'fail', retryable: true)
        b = described_class.new(message: 'fail', retryable: true)
        expect(a.hash).to eq(b.hash)
      end
    end
  end

  describe BSV::Network::Result::NotFound do
    it 'works with no arguments' do
      result = described_class.new
      expect(result.message).to be_nil
      expect(result.metadata).to eq({})
    end

    it 'accepts an optional message' do
      result = described_class.new(message: 'transaction not found')
      expect(result.message).to eq('transaction not found')
    end

    it 'defaults metadata to empty hash' do
      result = described_class.new
      expect(result.metadata).to eq({})
    end

    it 'stores explicit metadata' do
      result = described_class.new(metadata: { txid: 'abc' })
      expect(result.metadata).to eq({ txid: 'abc' })
    end

    it 'is frozen after construction' do
      result = described_class.new
      expect(result).to be_frozen
    end

    it 'returns false for success?' do
      expect(described_class.new.success?).to be false
    end

    it 'returns false for error?' do
      expect(described_class.new.error?).to be false
    end

    it 'returns true for not_found?' do
      expect(described_class.new.not_found?).to be true
    end

    describe 'equality' do
      it 'equals another NotFound with same attributes' do
        a = described_class.new(message: 'gone', metadata: { code: 404 })
        b = described_class.new(message: 'gone', metadata: { code: 404 })
        expect(a).to eq(b)
      end

      it 'does not equal a NotFound with different message' do
        a = described_class.new(message: 'gone')
        b = described_class.new(message: nil)
        expect(a).not_to eq(b)
      end

      it 'produces the same hash for equal instances' do
        a = described_class.new(message: 'gone')
        b = described_class.new(message: 'gone')
        expect(a.hash).to eq(b.hash)
      end
    end
  end

  describe 'cross-type inequality' do
    it 'Success does not equal Error' do
      expect(BSV::Network::Result::Success.new(data: nil)).not_to eq(BSV::Network::Result::Error.new(message: 'fail'))
    end

    it 'Success does not equal NotFound' do
      expect(BSV::Network::Result::Success.new(data: nil)).not_to eq(BSV::Network::Result::NotFound.new)
    end

    it 'Error does not equal NotFound' do
      expect(BSV::Network::Result::Error.new(message: 'fail')).not_to eq(BSV::Network::Result::NotFound.new)
    end
  end
end
