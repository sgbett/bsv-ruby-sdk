# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'
require 'securerandom'
require 'bsv/wallet/testing/shared_examples_for_wallet_operations'

STORE_FACTORIES.each do |label, store_factory|
  RSpec.describe "BSV::Wallet::LocalPool (#{label})" do
    let(:store) { store_factory.call }
    let(:store_label) { label }

    it_behaves_like 'wallet local pool'
  end
end
