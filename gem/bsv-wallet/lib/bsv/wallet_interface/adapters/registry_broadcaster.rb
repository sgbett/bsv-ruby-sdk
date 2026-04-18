# frozen_string_literal: true

module BSV
  module Wallet
    # Reverse adapter: wraps a {BSV::Network::Registry} as a legacy broadcaster duck type.
    #
    # Implements the +#broadcast(tx)+ contract expected by {InlineQueue} and
    # +promote_no_send+ inside {WalletClient}.
    #
    # On success, returns a {BSV::Network::BroadcastResponse} constructed from the
    # data in the registry result. On failure, raises {BSV::Network::BroadcastError}
    # so that rescue blocks in the broadcast queue and +promote_no_send+ can
    # trigger rollback correctly.
    #
    # IMPORTANT: This adapter MUST raise on failure rather than returning a Result.
    # The {InlineQueue} rescue block only detects failures via exceptions; a Result
    # return value would bypass rollback silently.
    #
    # @example
    #   broadcaster = BSV::Wallet::RegistryBroadcaster.new(registry)
    #   response = broadcaster.broadcast(tx) # raises BroadcastError on failure
    class RegistryBroadcaster
      # @param registry [BSV::Network::Registry] the network registry to dispatch through
      def initialize(registry)
        @registry = registry
      end

      # Broadcast a transaction via the registry's +:broadcast+ provider.
      #
      # @param tx [BSV::Transaction::Transaction] the transaction to broadcast
      # @return [BSV::Network::BroadcastResponse]
      # @raise [BSV::Network::BroadcastError] when the registry returns an error result or
      #   raises {BSV::Network::Registry::NoProviderError}
      def broadcast(tx)
        result = @registry.call(:broadcast, tx)

        unless result.success?
          meta = result.respond_to?(:metadata) ? result.metadata : {}
          raise BSV::Network::BroadcastError.new(
            result.message || 'Broadcast failed',
            arc_status: meta[:arc_status],
            txid: meta[:txid]
          )
        end

        build_response(result.data)
      rescue BSV::Network::Registry::NoProviderError => e
        raise BSV::Network::BroadcastError, e.message
      end

      private

      # Construct a {BroadcastResponse} from the data hash returned by a provider.
      #
      # Providers may return a full {BroadcastResponse} object (e.g. from a legacy
      # adapter wrapping ARC) or a plain hash with +:txid+ and optional +:status+.
      #
      # @param data [BSV::Network::BroadcastResponse, Hash] provider result data
      # @return [BSV::Network::BroadcastResponse]
      def build_response(data)
        return data if data.is_a?(BSV::Network::BroadcastResponse)

        BSV::Network::BroadcastResponse.new(
          txid: data[:txid],
          tx_status: data[:status] || data[:tx_status],
          message: data[:message],
          extra_info: data[:extra_info]
        )
      end
    end
  end
end
