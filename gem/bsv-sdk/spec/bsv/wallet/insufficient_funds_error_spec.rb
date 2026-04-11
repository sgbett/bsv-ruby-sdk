# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Wallet::InsufficientFundsError do
  it 'is a StandardError subclass' do
    expect(described_class).to be < StandardError
  end

  it 'stores required and available amounts' do
    error = described_class.new(required: 10_000, available: 5_000)
    expect(error.required).to eq(10_000)
    expect(error.available).to eq(5_000)
  end

  it 'generates a default message from required and available' do
    error = described_class.new(required: 10_000, available: 5_000)
    expect(error.message).to eq('insufficient funds: need 10000, have 5000')
  end

  it 'accepts a custom message' do
    error = described_class.new('custom message', required: 10_000, available: 5_000)
    expect(error.message).to eq('custom message')
  end

  it 'defaults required and available to nil' do
    error = described_class.new('oops')
    expect(error.required).to be_nil
    expect(error.available).to be_nil
  end
end
