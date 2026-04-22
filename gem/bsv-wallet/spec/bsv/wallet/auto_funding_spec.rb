# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'
require 'bsv/wallet/testing/shared_examples_for_wallet_operations'

# Comprehensive tests for auto-funding in Client#create_action.
#
# Auto-funding is triggered when create_action receives outputs but no inputs.
# The wallet selects spendable UTXOs with BRC-29 derivation metadata, estimates
# fees, generates change, builds and signs the transaction.

STORE_FACTORIES.each do |store_label, store_factory|
  RSpec.describe "Client auto-funding pipeline (#{store_label})" do
    let(:store) { store_factory.call }

    it_behaves_like 'wallet auto-funding'
  end
end
