# frozen_string_literal: true

# Live integration spec for ChainTracker.default against GorillaPool/JungleBus.
#
# Tagged :integration — runs only when BSV_INTEGRATION=true.
#
# Read-only; no funds required. No env vars beyond BSV_INTEGRATION needed.
#
# Run locally: BSV_INTEGRATION=true bundle exec rspec spec/bsv/transaction/chain_tracker_integration_spec.rb

require 'spec_helper'

RSpec.describe 'ChainTracker integration', :integration do # rubocop:disable RSpec/DescribeClass
  subject(:tracker) { BSV::Transaction::ChainTracker.default }

  # Block 800_000 — stable mid-chain anchor with known merkle root.
  # If JungleBus stops serving this for any reason, swap with any other
  # historic block + its real merkle root.
  let(:stable_height) { 800_000 }
  let(:stable_merkle_root) { '244993b9d8d961f5b4c91afa569adf9b6d8cd18e0bb6f769f5e62cdf2cc1468d' }

  it 'returns a current tip height' do
    expect(tracker.current_height).to be > stable_height
  end

  it 'validates a known merkle root at a stable height' do
    expect(tracker.valid_root_for_height?(stable_merkle_root, stable_height)).to be(true)
  end

  it 'rejects a wrong merkle root at a stable height' do
    expect(tracker.valid_root_for_height?('00' * 32, stable_height)).to be(false)
  end
end
