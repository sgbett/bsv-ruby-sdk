# frozen_string_literal: true

module BSV
  module Wallet
    # Default chain provider that raises for all blockchain queries.
    #
    # Used when a WalletClient is constructed without a chain provider,
    # allowing the wallet to function for transaction and crypto operations
    # without requiring a blockchain connection.
    class NullChainProvider
      include ChainProvider

      def get_height
        raise UnsupportedActionError, 'get_height (no chain provider configured)'
      end

      def get_header(_height)
        raise UnsupportedActionError, 'get_header_for_height (no chain provider configured)'
      end
    end
  end
end
