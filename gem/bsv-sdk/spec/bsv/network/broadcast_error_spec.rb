# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Network::BroadcastError do
  it 'is a StandardError' do
    expect(described_class).to be < StandardError
  end

  it 'stores message, status_code, and txid' do
    error = described_class.new('rejected', status_code: 465, txid: 'abc123')

    expect(error.message).to eq('rejected')
    expect(error.status_code).to eq(465)
    expect(error.txid).to eq('abc123')
  end

  it 'defaults status_code and txid to nil' do
    error = described_class.new('something failed')

    expect(error.status_code).to be_nil
    expect(error.txid).to be_nil
  end

  it 'can be raised and rescued' do
    expect do
      raise described_class, 'broadcast failed'
    end.to raise_error(described_class, 'broadcast failed')
  end
end
