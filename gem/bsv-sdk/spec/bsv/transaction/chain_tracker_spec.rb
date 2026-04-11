# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Transaction::ChainTracker do
  subject(:tracker) { described_class.new }

  describe '#valid_root_for_height?' do
    it 'raises NotImplementedError' do
      expect { tracker.valid_root_for_height?('abc', 100) }
        .to raise_error(NotImplementedError, /valid_root_for_height\? must be implemented/)
    end
  end

  describe '#current_height' do
    it 'raises NotImplementedError' do
      expect { tracker.current_height }
        .to raise_error(NotImplementedError, /current_height must be implemented/)
    end
  end

  context 'with a concrete subclass' do
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
