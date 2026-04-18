# frozen_string_literal: true

module BSV
  module Wallet
    # Default chain provider that raises for all blockchain queries.
    #
    # @deprecated Use an empty {BSV::Network::Registry} instead (or omit the +chain_provider:+
    #   param entirely — WalletClient now defaults to an empty Registry when no +network:+
    #   Registry or legacy provider is supplied).
    #
    # @see https://github.com/sgbett/bsv-ruby-sdk/issues/498
    class NullChainProvider
      include ChainProvider

      def initialize
        return if ENV['BSV_SUPPRESS_DEPRECATIONS']

        self.class.instance_variable_get(:@deprecation_warnings) ||
          self.class.instance_variable_set(:@deprecation_warnings, {})
        return if self.class.instance_variable_get(:@deprecation_warnings)[:new]

        warn '[DEPRECATION] BSV::Wallet::NullChainProvider is deprecated. ' \
             'An empty BSV::Network::Registry is the replacement — omit chain_provider: to use it. ' \
             'See https://github.com/sgbett/bsv-ruby-sdk/issues/498'
        self.class.instance_variable_get(:@deprecation_warnings)[:new] = true
      end

      def get_height
        raise UnsupportedActionError, 'get_height (no chain provider configured)'
      end

      def get_header(_height)
        raise UnsupportedActionError, 'get_header (no chain provider configured)'
      end

      def get_utxos(_address)
        raise UnsupportedActionError, 'get_utxos (no chain provider configured)'
      end

      def get_transaction(_txid)
        raise UnsupportedActionError, 'get_transaction (no chain provider configured)'
      end
    end
  end
end
