# frozen_string_literal: true

RSpec.describe BSV::Network::ChainProviderError do
  it 'is a StandardError subclass' do
    expect(described_class).to be < StandardError
  end

  it 'stores the message' do
    error = described_class.new('something went wrong')
    expect(error.message).to eq('something went wrong')
  end

  it 'stores the status_code' do
    error = described_class.new('not found', status_code: 404)
    expect(error.status_code).to eq(404)
  end

  it 'defaults status_code to nil' do
    error = described_class.new('oops')
    expect(error.status_code).to be_nil
  end
end
