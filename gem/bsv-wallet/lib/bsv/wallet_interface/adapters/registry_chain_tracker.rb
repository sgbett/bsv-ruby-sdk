# frozen_string_literal: true

module BSV
  module Wallet
    # Reverse adapter: wraps a {BSV::Network::Registry} as a chain tracker duck type.
    #
    # Responds to +#valid_root_for_height?(root, height)+ by dispatching the
    # +:valid_root+ command through the registry. Used by +internalize_action+ for
    # BEEF verification when no legacy ChainProvider is available.
    #
    # When no provider is registered for +:valid_root+, returns +false+ as a safe
    # default rather than raising — this matches the existing behaviour of
    # +internalize_action+, which guards the call with +respond_to?+. Returning
    # +false+ ensures BEEF verification fails closed rather than open.
    #
    # @example
    #   tracker = BSV::Wallet::RegistryChainTracker.new(registry)
    #   tracker.valid_root_for_height?('aabbcc...', 850_000)
    class RegistryChainTracker
      # @param registry [BSV::Network::Registry] the network registry to dispatch through
      def initialize(registry)
        @registry = registry
      end

      # Verify that a Merkle root matches the block header at the given height.
      #
      # Delegates to the registry's +:valid_root+ command. Returns +false+ when
      # no provider is registered (safe default for SPV verification).
      #
      # @param root [String] Merkle root as a hex string
      # @param height [Integer] block height
      # @return [Boolean]
      def valid_root_for_height?(root, height)
        result = @registry.call(:valid_root, root, height)
        result.success? && result.data == true
      rescue BSV::Network::Registry::NoProviderError
        false
      end

      # Return the current blockchain height via the registry.
      #
      # Returns +nil+ when no provider is registered for +:current_height+.
      #
      # @return [Integer, nil]
      def current_height
        result = @registry.call(:current_height)
        result.success? ? result.data : nil
      rescue BSV::Network::Registry::NoProviderError
        nil
      end
    end
  end
end
