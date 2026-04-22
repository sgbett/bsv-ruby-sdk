# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'
require 'bsv/wallet/testing/shared_examples_for_wallet_operations'

# End-to-end round-trip spec for HLR #466.
#
# Exercises the full lifecycle:
#   1. Build a synthetic 2-generation BEEF (grandparent confirmed, parent raw).
#   2. internalize_action — wallet stores the BEEF contents (subject output + ancestors).
#   3. create_action — spend the internalised output; wallet builds a new tx with ancestry.
#   4. Mocked ARC accepts the broadcast by calling tx.to_ef_hex — proves EF serialises.

STORE_FACTORIES.each do |store_label, store_factory|
  RSpec.describe "BEEF ancestry round-trip (HLR #466) (#{store_label})" do
    let(:store) { store_factory.call }

    it_behaves_like 'wallet BEEF ancestry round-trip'
  end
end
