# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'
require 'securerandom'
require 'bsv/wallet/testing/shared_examples_for_wallet_operations'

# Integration specs for broadcast_and_promote and promote_no_send flows.
#
# These specs exercise the combined behaviour introduced by Tasks 1-3 of HLR #379:
#   - Task 1: change outputs stored as :pending immediately (TOCTOU fix)
#   - Task 2: broadcast and promotion error handling are isolated
#   - Task 3: per-tx rollback for send_with batch broadcasts

STORE_FACTORIES.each do |store_label, store_factory|
  RSpec.describe "broadcast_and_promote and promote_no_send integration (#{store_label})" do
    let(:store) { store_factory.call }

    it_behaves_like 'wallet broadcast rollback'
  end
end
