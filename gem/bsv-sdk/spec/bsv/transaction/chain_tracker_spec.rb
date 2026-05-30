# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Transaction::ChainTracker do
  let(:provider) { instance_double(BSV::Network::Provider) }

  describe '.default' do
    it 'returns a ChainTracker instance' do
      tracker = described_class.default
      expect(tracker).to be_a(described_class)
    end

    it 'returns a ChainTracker backed by a GorillaPool mainnet provider' do
      tracker = described_class.default
      expect(tracker.instance_variable_get(:@provider).name).to eq('GorillaPool')
    end

    it 'returns a testnet ChainTracker when testnet: true' do
      tracker = described_class.default(testnet: true)
      expect(tracker).to be_a(described_class)
    end

    it 'testnet tracker is backed by a GorillaPool provider' do
      tracker = described_class.default(testnet: true)
      expect(tracker.instance_variable_get(:@provider).name).to eq('GorillaPool')
    end
  end

  describe '.new' do
    it 'constructs with no arguments' do
      expect { described_class.new }.not_to raise_error
    end

    it 'constructs with a provider' do
      expect { described_class.new(provider) }.not_to raise_error
    end
  end

  describe '#valid_root_for_height?' do
    context 'with no provider' do
      subject(:tracker) { described_class.new }

      it 'raises a clear error' do
        expect { tracker.valid_root_for_height?('abc', 100) }
          .to raise_error(RuntimeError, /requires a provider/)
      end
    end

    context 'with a provider' do
      subject(:tracker) { described_class.new(provider) }

      def stub_header(data)
        response = instance_double(BSV::Network::ProtocolResponse,
                                   http_not_found?: false,
                                   http_success?: true,
                                   data: data)
        allow(provider).to receive(:call).with(:get_block_header, anything).and_return(response)
      end

      def stub_not_found
        response = instance_double(BSV::Network::ProtocolResponse,
                                   http_not_found?: true,
                                   http_success?: false)
        allow(provider).to receive(:call).with(:get_block_header, anything).and_return(response)
      end

      def stub_error(message)
        response = instance_double(BSV::Network::ProtocolResponse,
                                   http_not_found?: false,
                                   http_success?: false,
                                   error_message: message)
        allow(provider).to receive(:call).with(:get_block_header, anything).and_return(response)
      end

      it 'returns true when root matches (lowercase field name)' do
        stub_header('merkleroot' => 'abc')
        expect(tracker.valid_root_for_height?('ABC', 800_000)).to be true
      end

      it 'returns true when root matches (camelCase field name)' do
        stub_header('merkleRoot' => 'abc')
        expect(tracker.valid_root_for_height?('ABC', 800_000)).to be true
      end

      it 'returns true when root matches (snake_case field name)' do
        stub_header('merkle_root' => 'abc')
        expect(tracker.valid_root_for_height?('ABC', 800_000)).to be true
      end

      it 'returns true when root matches with identical casing' do
        stub_header('merkleroot' => 'abc123')
        expect(tracker.valid_root_for_height?('abc123', 800_000)).to be true
      end

      it 'returns false when root does not match' do
        stub_header('merkleroot' => 'abc')
        expect(tracker.valid_root_for_height?('zzz', 800_000)).to be false
      end

      it 'returns false on 404' do
        stub_not_found
        expect(tracker.valid_root_for_height?('abc', 800_000)).to be false
      end

      it 'returns false when header response lacks any merkle-root field' do
        stub_header('hash' => 'xyz', 'height' => 800_000)
        expect(tracker.valid_root_for_height?('abc', 800_000)).to be false
      end

      it 'returns false when header response data is not a Hash' do
        stub_header('not a hash')
        expect(tracker.valid_root_for_height?('abc', 800_000)).to be false
      end

      it 'raises on non-success non-404 response' do
        stub_error('internal server error')
        expect { tracker.valid_root_for_height?('abc', 800_000) }
          .to raise_error(RuntimeError, 'internal server error')
      end
    end
  end

  describe '#current_height' do
    context 'with no provider' do
      subject(:tracker) { described_class.new }

      it 'raises a clear error' do
        expect { tracker.current_height }
          .to raise_error(RuntimeError, /requires a provider/)
      end
    end

    context 'with a provider' do
      subject(:tracker) { described_class.new(provider) }

      it 'returns the integer height on success' do
        response = instance_double(BSV::Network::ProtocolResponse,
                                   http_success?: true,
                                   data: 830_000)
        allow(provider).to receive(:call).with(:current_height).and_return(response)

        expect(tracker.current_height).to eq(830_000)
      end

      it 'raises on failure' do
        response = instance_double(BSV::Network::ProtocolResponse,
                                   http_success?: false,
                                   error_message: 'service unavailable')
        allow(provider).to receive(:call).with(:current_height).and_return(response)

        expect { tracker.current_height }
          .to raise_error(RuntimeError, 'service unavailable')
      end
    end
  end

  context 'with a concrete subclass overriding both methods' do
    let(:concrete_tracker_class) do
      Class.new(described_class) do
        def valid_root_for_height?(root, height)
          root == 'valid_root' && height == 100
        end

        def current_height
          800_000
        end
      end
    end

    let(:concrete) { concrete_tracker_class.new }

    it 'constructs without a provider' do
      expect { concrete_tracker_class.new }.not_to raise_error
    end

    it 'returns true for matching root and height' do
      expect(concrete.valid_root_for_height?('valid_root', 100)).to be true
    end

    it 'returns false for non-matching root' do
      expect(concrete.valid_root_for_height?('bad_root', 100)).to be false
    end

    it 'returns current height' do
      expect(concrete.current_height).to eq(800_000)
    end
  end
end
