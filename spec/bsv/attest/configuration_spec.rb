# frozen_string_literal: true

require 'bsv-attest'

RSpec.describe BSV::Attest::Configuration do
  subject(:config) { described_class.new }

  it 'defaults wallet to nil' do
    expect(config.wallet).to be_nil
  end

  it 'defaults broadcaster to nil' do
    expect(config.broadcaster).to be_nil
  end

  it 'defaults provider to nil' do
    expect(config.provider).to be_nil
  end

  it 'supports setting all three attributes' do
    wallet = Object.new
    broadcaster = Object.new
    provider = Object.new

    config.wallet = wallet
    config.broadcaster = broadcaster
    config.provider = provider

    expect(config.wallet).to eq(wallet)
    expect(config.broadcaster).to eq(broadcaster)
    expect(config.provider).to eq(provider)
  end
end
