# frozen_string_literal: true

require 'spec_helper'

# Keyless, read-only checks that the SDK's default broadcast services are
# reachable and still speak the shapes the protocols parse. No key, no spend.
# Asserts shape rather than values: fees and policies drift. Only HTTP 429 is
# treated as an acceptable flake.
RSpec.describe 'Default broadcast services', :integration do # rubocop:disable RSpec/DescribeClass
  def call_or_skip(provider, command, *)
    result = provider.call(command, *)
    skip "#{provider.name} rate-limited (429)" if result.code == '429'
    result
  end

  shared_examples 'a live ARC-compatible service' do
    it 'reports healthy' do
      expect(call_or_skip(provider, :health)).to be_http_success
    end

    it 'publishes a mining fee policy' do
      result = call_or_skip(provider, :get_policy)
      fee = result.data.dig('policy', 'miningFee')

      aggregate_failures do
        expect(result).to be_http_success
        expect(fee['satoshis']).to be_an(Integer)
        expect(fee['bytes']).to be_an(Integer)
      end
    end
  end

  { 'mainnet' => false, 'testnet' => true }.each do |label, testnet|
    describe "GorillaPool ARC (#{label})" do
      let(:provider) { BSV::Network::Providers::GorillaPool.default(testnet: testnet) }

      it_behaves_like 'a live ARC-compatible service'
    end

    describe "BSV Association Broadcaster (#{label})" do
      let(:provider) { BSV::Network::Providers::BSVAssociation.default(testnet: testnet) }

      it_behaves_like 'a live ARC-compatible service'

      it 'reports a well-formed unknown txid as not found' do
        result = call_or_skip(provider, :get_tx_status, "#{'00' * 31}01")

        aggregate_failures do
          expect(result).to be_http_not_found
          expect(result.error_message).to eq('transaction not found')
        end
      end
    end
  end

  describe 'LivePolicy.default' do
    it 'parses the live GorillaPool policy rather than falling back' do
      fallback = 999_999
      policy = BSV::Transaction::FeeModels::LivePolicy.new(
        arc_url: BSV::Transaction::FeeModels::LivePolicy.default.arc_url,
        fallback_rate: fallback
      )

      rate = policy.current_rate

      aggregate_failures do
        expect(rate).not_to eq(fallback)
        expect(rate).to be_an(Integer)
        expect(rate).to be >= 1
      end
    end
  end
end
