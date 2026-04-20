# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::WalletError do
  it 'inherits from StandardError' do
    expect(described_class.ancestors).to include(StandardError)
  end

  it 'has a default error code of 1' do
    error = described_class.new('test')
    expect(error.code).to eq(1)
    expect(error.message).to eq('test')
  end

  it 'accepts a custom error code' do
    error = described_class.new('test', 42)
    expect(error.code).to eq(42)
  end
end

RSpec.describe BSV::Wallet::InvalidParameterError do
  it 'inherits from WalletError' do
    expect(described_class.ancestors).to include(BSV::Wallet::WalletError)
  end

  it 'has error code 6' do
    error = described_class.new('foo')
    expect(error.code).to eq(6)
  end

  it 'stores the parameter name' do
    error = described_class.new('protocol_id', 'an Array')
    expect(error.parameter).to eq('protocol_id')
    expect(error.message).to include('protocol_id')
    expect(error.message).to include('an Array')
  end

  it 'uses a default must_be value of "valid"' do
    error = described_class.new('key_id')
    expect(error.message).to include('valid')
  end
end

RSpec.describe BSV::Wallet::InvalidHmacError do
  it 'inherits from WalletError' do
    expect(described_class.ancestors).to include(BSV::Wallet::WalletError)
  end

  it 'has error code 3' do
    expect(described_class.new.code).to eq(3)
  end

  it 'has a default message mentioning HMAC' do
    expect(described_class.new.message).to include('HMAC')
  end

  it 'accepts a custom message' do
    error = described_class.new('custom hmac message')
    expect(error.message).to eq('custom hmac message')
  end
end

RSpec.describe BSV::Wallet::InvalidSignatureError do
  it 'inherits from WalletError' do
    expect(described_class.ancestors).to include(BSV::Wallet::WalletError)
  end

  it 'has error code 4' do
    expect(described_class.new.code).to eq(4)
  end

  it 'has a default message mentioning signature' do
    expect(described_class.new.message).to include('signature')
  end

  it 'accepts a custom message' do
    error = described_class.new('custom sig message')
    expect(error.message).to eq('custom sig message')
  end
end

RSpec.describe BSV::Wallet::UnsupportedActionError do
  it 'inherits from WalletError' do
    expect(described_class.ancestors).to include(BSV::Wallet::WalletError)
  end

  it 'has error code 2' do
    expect(described_class.new.code).to eq(2)
  end

  it 'includes the method name in the message' do
    error = described_class.new('create_action')
    expect(error.message).to include('create_action')
  end

  it 'uses a default method name when none is given' do
    error = described_class.new
    expect(error.message).to include('this method')
  end
end
