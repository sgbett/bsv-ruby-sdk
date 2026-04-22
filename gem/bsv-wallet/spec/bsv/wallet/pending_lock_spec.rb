# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'
require 'securerandom'
require 'time'
require 'bsv/wallet/testing/shared_examples_for_wallet_operations'

STORE_FACTORIES.each do |store_label, store_factory|
  RSpec.describe "Pending UTXO locking and double-spend prevention (#{store_label})" do
    let(:store) { store_factory.call }

    it_behaves_like 'wallet UTXO pending locks'
  end
end
