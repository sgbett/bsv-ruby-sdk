# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Network::WhatsOnChain do
  describe '.new' do
    it 'raises DeprecationError directing callers to Protocols::WoCREST' do
      expect { described_class.new }
        .to raise_error(BSV::Network::WhatsOnChain::DeprecationError, /Protocols::WoCREST/)
    end
  end

  describe '.default' do
    it 'raises DeprecationError directing callers to Protocols::WoCREST' do
      expect { described_class.default }
        .to raise_error(BSV::Network::WhatsOnChain::DeprecationError, /Protocols::WoCREST/)
    end
  end
end
