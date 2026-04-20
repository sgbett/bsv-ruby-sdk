# frozen_string_literal: true

require_relative 'fee_estimator'

module BSV
  module Wallet
    # Backward-compatible alias for {FeeEstimator}.
    #
    # All fee estimation is consolidated in {FeeEstimator}, which provides
    # both pre-construction estimation (+estimate+) and post-construction
    # delegation (+compute+ / +estimate_for_tx+). This alias ensures
    # existing code referencing +FeeModel+ continues to work.
    #
    # @example
    #   model = BSV::Wallet::FeeModel.new(sats_per_kb: 50)
    #   model.estimate(p2pkh_inputs: 2, p2pkh_outputs: 3)
    #   model.compute(transaction)
    #   model.dust_floor
    FeeModel = FeeEstimator
  end
end
