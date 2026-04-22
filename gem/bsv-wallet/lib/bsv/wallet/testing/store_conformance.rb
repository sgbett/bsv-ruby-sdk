# frozen_string_literal: true

# Convenience loader for all bsv-wallet shared test support.
#
# Downstream adapter gems can load the full suite in one line:
#
#   require 'bsv/wallet/testing/store_conformance'
#
# This provides:
#   - 'a storage adapter'  — interface-level CRUD conformance
#   - 'wallet auto-funding', 'wallet certificate operations', etc.
#     — wallet-level operation shared examples

require_relative 'shared_examples_for_storage_adapter'
require_relative 'shared_examples_for_wallet_operations'
