# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'
require 'bsv/wallet/testing/shared_examples_for_wallet_operations'

STORE_FACTORIES.each do |store_label, store_factory|
  RSpec.describe "#{BSV::Wallet::BroadcastQueue::Inline} (#{store_label})" do
    let(:store) { store_factory.call }

    it_behaves_like 'wallet inline broadcast queue'
  end
end
