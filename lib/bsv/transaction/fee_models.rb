# frozen_string_literal: true

module BSV
  module Transaction
    # Namespace for fee model implementations.
    module FeeModels
      autoload :SatoshisPerKilobyte, 'bsv/transaction/fee_models/satoshis_per_kilobyte'
      autoload :LivePolicy,          'bsv/transaction/fee_models/live_policy'
    end
  end
end
