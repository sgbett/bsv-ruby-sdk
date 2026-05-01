# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Network::ARC do
  describe '.new' do
    it 'raises DeprecationError directing callers to Protocols::ARC' do
      expect { described_class.new('https://arc.example.com') }
        .to raise_error(BSV::Network::ARC::DeprecationError, /Protocols::ARC/)
    end
  end

  describe '.default' do
    it 'raises DeprecationError directing callers to Protocols::ARC' do
      expect { described_class.default }
        .to raise_error(BSV::Network::ARC::DeprecationError, /Protocols::ARC/)
    end
  end
end
