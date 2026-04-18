# frozen_string_literal: true

module BSV
  module Wallet
    # Forward adapter: wraps a legacy broadcaster duck type as a {BSV::Network::Provider}.
    #
    # Registers the +:broadcast+ capability and delegates to the wrapped object's
    # +#broadcast(tx)+ method. Catches {BSV::Network::BroadcastError} and any
    # other exception, returning a non-retryable +Result::Error+ in both cases.
    #
    # On success, returns +Result::Success+ carrying the {BSV::Network::BroadcastResponse}
    # returned by the underlying broadcaster.
    #
    # @example
    #   arc = BSV::Network::ARC.new(url)
    #   adapter = BSV::Wallet::LegacyBroadcasterAdapter.new(arc)
    #   registry = BSV::Network::Registry.new
    #   registry.register(adapter)
    class LegacyBroadcasterAdapter < BSV::Network::Provider
      provides :broadcast

      # @param broadcaster [#broadcast] legacy broadcaster (e.g. {BSV::Network::ARC})
      def initialize(broadcaster)
        super()
        unless ENV['BSV_SUPPRESS_DEPRECATIONS']
          self.class.instance_variable_get(:@deprecation_warnings) ||
            self.class.instance_variable_set(:@deprecation_warnings, {})
          unless self.class.instance_variable_get(:@deprecation_warnings)[:new]
            warn '[DEPRECATION] broadcaster: is deprecated. ' \
                 'Pass a BSV::Network::Registry with a broadcast provider via network: instead. ' \
                 'See https://github.com/sgbett/bsv-ruby-sdk/issues/498'
            self.class.instance_variable_get(:@deprecation_warnings)[:new] = true
          end
        end
        @broadcaster = broadcaster
      end

      private

      # Broadcast a transaction via the legacy broadcaster.
      #
      # @param tx [BSV::Transaction::Transaction] the transaction to broadcast
      # @return [Result::Success, Result::Error]
      def call_broadcast(tx)
        response = @broadcaster.broadcast(tx)
        success(response)
      rescue BSV::Network::BroadcastError, StandardError => e
        error(e.message, retryable: false)
      end
    end
  end
end
