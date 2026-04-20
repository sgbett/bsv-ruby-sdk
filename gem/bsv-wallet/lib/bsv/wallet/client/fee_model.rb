# frozen_string_literal: true

require_relative 'fee_estimator'

module BSV
  module Wallet
    # Backward-compatible alias for {FeeEstimator}.
    #
    # All fee estimation is consolidated in {FeeEstimator}. This alias ensures
    # existing code referencing +FeeModel+ continues to work.
    FeeModel = FeeEstimator
  end
end
