# frozen_string_literal: true

require 'spec_helper'

require 'bsv-attest'

RSpec.describe BSV::Attest::BroadcastError do
  it 'is a StandardError subclass' do
    expect(described_class).to be < StandardError
  end

  it 'stores a message' do
    error = described_class.new('broadcast failed')
    expect(error.message).to eq('broadcast failed')
  end
end
