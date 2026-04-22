# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'
require 'tmpdir'
require 'bsv/wallet/testing/shared_examples_for_wallet_operations'

STORE_FACTORIES.each do |label, store_factory|
  RSpec.describe "Pool health and configurable change parameters (#{label})" do
    let(:store) { store_factory.call }
    let(:store_label) { label }

    it_behaves_like 'wallet pool health'
  end
end
