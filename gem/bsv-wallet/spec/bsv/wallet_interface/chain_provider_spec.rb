# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::ChainProvider do
  let(:provider_class) { Class.new { include BSV::Wallet::ChainProvider } }
  let(:provider) { provider_class.new }

  it 'raises NotImplementedError for get_height' do
    expect { provider.get_height }.to raise_error(NotImplementedError)
  end

  it 'raises NotImplementedError for get_header' do
    expect { provider.get_header(1) }.to raise_error(NotImplementedError)
  end
end

RSpec.describe BSV::Wallet::NullChainProvider do
  let(:provider) { described_class.new }

  it 'raises UnsupportedActionError for get_height' do
    expect { provider.get_height }.to raise_error(BSV::Wallet::UnsupportedActionError)
  end

  it 'raises UnsupportedActionError for get_header' do
    expect { provider.get_header(1) }.to raise_error(BSV::Wallet::UnsupportedActionError)
  end
end
