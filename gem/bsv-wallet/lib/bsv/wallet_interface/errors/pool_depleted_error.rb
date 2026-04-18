# frozen_string_literal: true

module BSV
  module Wallet
    # Raised when a UTXO pool has no available outputs for acquisition.
    class PoolDepletedError < WalletError
      def initialize(pool_name)
        super("UTXO pool '#{pool_name}' is depleted; no outputs available for acquisition")
      end
    end
  end
end
