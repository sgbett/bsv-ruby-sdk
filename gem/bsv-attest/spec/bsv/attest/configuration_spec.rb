# frozen_string_literal: true

require 'spec_helper'

require 'bsv-attest'

RSpec.describe BSV::Attest::Configuration do
  subject(:config) { described_class.new }

  it 'defaults wallet to nil' do
    expect(config.wallet).to be_nil
  end

  it 'defaults provider to nil' do
    expect(config.provider).to be_nil
  end

  it 'supports setting all attributes' do
    wallet = Object.new
    provider = Object.new

    config.wallet = wallet
    config.provider = provider

    expect(config.wallet).to eq(wallet)
    expect(config.provider).to eq(provider)
  end

  it 'does not respond to broadcaster' do
    expect(config).not_to respond_to(:broadcaster)
  end
end
