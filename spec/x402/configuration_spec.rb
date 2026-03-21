# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe BSV::X402::Configuration do
  subject(:config) { described_class.new }

  describe 'defaults' do
    it 'defaults payee_locking_script_hex to nil' do
      expect(config.payee_locking_script_hex).to be_nil
    end

    it 'defaults amount_sats to 100' do
      expect(config.amount_sats).to eq(100)
    end

    it 'defaults nonce_provider to nil' do
      expect(config.nonce_provider).to be_nil
    end

    it 'defaults broadcaster to nil' do
      expect(config.broadcaster).to be_nil
    end

    it 'defaults expires_in to 300' do
      expect(config.expires_in).to eq(300)
    end

    it 'defaults bound_headers to an empty array' do
      expect(config.bound_headers).to eq([])
    end
  end

  describe 'attribute assignment' do
    it 'accepts a payee_locking_script_hex' do
      config.payee_locking_script_hex = '76a914aabbcc' \
                                        '00000000000000000000000000000088ac'
      expect(config.payee_locking_script_hex).to start_with('76a914')
    end

    it 'accepts an amount_sats value' do
      config.amount_sats = 1000
      expect(config.amount_sats).to eq(1000)
    end

    it 'accepts a nonce_provider' do
      provider = Object.new
      config.nonce_provider = provider
      expect(config.nonce_provider).to equal(provider)
    end

    it 'accepts a broadcaster' do
      broadcaster = Object.new
      config.broadcaster = broadcaster
      expect(config.broadcaster).to equal(broadcaster)
    end

    it 'accepts an expires_in value' do
      config.expires_in = 600
      expect(config.expires_in).to eq(600)
    end

    it 'accepts a bound_headers array' do
      config.bound_headers = %w[x-api-version content-type]
      expect(config.bound_headers).to eq(%w[x-api-version content-type])
    end
  end
end
