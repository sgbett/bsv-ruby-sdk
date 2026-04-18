# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe 'BSV::Network::Result' do
  let(:success) { BSV::Network::Result::Success.new(data: 'payload') }
  let(:success_nil) { BSV::Network::Result::Success.new(data: nil) }
  let(:error_retryable) { BSV::Network::Result::Error.new('timeout', retryable: true) }
  let(:error_not_retryable) { BSV::Network::Result::Error.new('bad request', retryable: false) }
  let(:error_nil_retryable) { BSV::Network::Result::Error.new('unknown', retryable: nil) }
  let(:not_found) { BSV::Network::Result::NotFound.new }

  describe 'BSV::Network::Result::Success' do
    it 'reports success? as true' do
      expect(success.success?).to be true
    end

    it 'reports error? as false' do
      expect(success.error?).to be false
    end

    it 'reports not_found? as false' do
      expect(success.not_found?).to be false
    end

    it 'exposes the data attribute' do
      expect(success.data).to eq('payload')
    end

    it 'accepts nil data' do
      expect(success_nil.data).to be_nil
      expect(success_nil.success?).to be true
    end

    it 'is frozen after initialisation' do
      expect(success).to be_frozen
    end

    it 'is equal to another Success with the same data' do
      expect(BSV::Network::Result::Success.new(data: 'payload')).to eq(success)
    end

    it 'is not equal to a Success with different data' do
      expect(BSV::Network::Result::Success.new(data: 'other')).not_to eq(success)
    end

    it 'is not equal to a NotFound' do
      expect(success_nil).not_to eq(not_found)
    end
  end

  describe 'BSV::Network::Result::Error' do
    it 'reports error? as true' do
      expect(error_retryable.error?).to be true
    end

    it 'reports success? as false' do
      expect(error_retryable.success?).to be false
    end

    it 'reports not_found? as false' do
      expect(error_retryable.not_found?).to be false
    end

    it 'exposes the message attribute' do
      expect(error_retryable.message).to eq('timeout')
    end

    it 'exposes the retryable attribute' do
      expect(error_retryable.retryable).to be true
    end

    it 'reports retryable? as true when retryable is true' do
      expect(error_retryable.retryable?).to be true
    end

    it 'reports retryable? as false when retryable is false' do
      expect(error_not_retryable.retryable?).to be false
    end

    it 'reports retryable? as false when retryable is nil' do
      expect(error_nil_retryable.retryable?).to be false
    end

    it 'defaults retryable to false when not supplied' do
      err = BSV::Network::Result::Error.new('oops')
      expect(err.retryable?).to be false
    end

    it 'is frozen after initialisation' do
      expect(error_retryable).to be_frozen
    end

    it 'is equal to another Error with the same message and retryable flag' do
      expect(BSV::Network::Result::Error.new('timeout', retryable: true)).to eq(error_retryable)
    end

    it 'is not equal to an Error with a different message' do
      expect(BSV::Network::Result::Error.new('different', retryable: true)).not_to eq(error_retryable)
    end

    it 'is not equal to an Error with a different retryable flag' do
      expect(BSV::Network::Result::Error.new('timeout', retryable: false)).not_to eq(error_retryable)
    end

    it 'is not equal to a Success' do
      expect(error_retryable).not_to eq(success)
    end
  end

  describe 'BSV::Network::Result::NotFound' do
    it 'reports not_found? as true' do
      expect(not_found.not_found?).to be true
    end

    it 'reports success? as false' do
      expect(not_found.success?).to be false
    end

    it 'reports error? as false' do
      expect(not_found.error?).to be false
    end

    it 'is frozen after initialisation' do
      expect(not_found).to be_frozen
    end

    it 'is equal to another NotFound' do
      expect(BSV::Network::Result::NotFound.new).to eq(not_found)
    end

    it 'is not equal to a Success with nil data' do
      expect(not_found).not_to eq(success_nil)
    end

    it 'is not equal to an Error' do
      expect(not_found).not_to eq(error_not_retryable)
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
