# frozen_string_literal: true

require 'bsv-attest'

RSpec.describe BSV::Attest::VerificationError do
  it 'is a StandardError subclass' do
    expect(described_class).to be < StandardError
  end

  it 'stores a message' do
    error = described_class.new('hash not found in transaction')
    expect(error.message).to eq('hash not found in transaction')
  end
end
