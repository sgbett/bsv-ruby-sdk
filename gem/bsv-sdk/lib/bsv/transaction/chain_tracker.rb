# frozen_string_literal: true

module BSV
  module Transaction
    # Duck type for block header lookups used by the SDK's verify methods.
    #
    # {Beef#verify}, {MerklePath#verify}, and {Transaction#verify} define
    # what a valid structure *is* — they walk trees, check proofs, and
    # compare roots. But they have no data source of their own. The
    # chain tracker is the data source: an object the consumer provides
    # that can answer "is this merkle root valid for this block height?"
    #
    # This class is a working default implementation that wraps a
    # {BSV::Network::Provider} and dispatches via {Provider#call}. The
    # provider must serve the +:get_block_header+ and +:current_height+
    # commands (e.g. a provider configured with {Protocols::JungleBus}).
    #
    # Subclasses may override either or both methods to supply their own
    # data source (in-memory hash, database cache, etc.) without touching
    # the provider at all. The +provider+ argument is optional precisely to
    # preserve this pattern — a subclass that overrides both methods never
    # reaches the provider-dispatch path.
    #
    # Any object responding to +valid_root_for_height?+ and
    # +current_height+ satisfies this interface. Inheriting from this
    # class is optional — it exists to document the contract and provide
    # a ready-to-use provider-backed implementation.
    #
    # @example In-memory chain tracker (test / declarative)
    #   class HashTracker < BSV::Transaction::ChainTracker
    #     def initialize(headers)  @headers = headers end
    #     def valid_root_for_height?(root, h) @headers[h] == root end
    #     def current_height() @headers.keys.max end
    #   end
    #   tracker = HashTracker.new(800_000 => 'abcd...')
    #
    # @example Cache-aware chain tracker (production / imperative)
    #   class WalletChainTracker < BSV::Transaction::ChainTracker
    #     def valid_root_for_height?(root, height)
    #       header = @db.find_header(height) || fetch_and_store(height)
    #       header.merkle_root == root
    #     end
    #   end
    #
    # @example Provider-backed (default impl)
    #   tracker = BSV::Transaction::ChainTracker.default
    #   tracker.valid_root_for_height?('abcd...', 800_000)
    #
    # @example Testnet
    #   tracker = BSV::Transaction::ChainTracker.default(testnet: true)
    #   tracker.current_height
    class ChainTracker
      # @return [BSV::Network::Provider, nil] the underlying provider, if any
      attr_reader :provider

      # Return a default ChainTracker backed by the GorillaPool provider.
      #
      # @param testnet [Boolean] when true, uses the testnet provider
      # @return [ChainTracker]
      def self.default(testnet: false)
        new(BSV::Network::Providers::GorillaPool.default(testnet: testnet))
      end

      # @param provider [BSV::Network::Provider, nil] provider serving +:get_block_header+
      #   and +:current_height+. Optional when the subclass overrides both methods.
      def initialize(provider = nil)
        @provider = provider
      end

      # Verify that a merkle root is valid for the given block height.
      #
      # Dispatches +:get_block_header+ to the configured provider. Returns +false+
      # on 404 (block not found). Relies on the wire-protocol classes
      # (+Protocols::ARC+, +Protocols::JungleBus+, etc.) to emit the canonical
      # +merkle_root+ key — see issue #791 / PR for the Pattern A normalisation
      # that absorbed the previous field-name shim.
      #
      # @param root [String] merkle root as a hex string
      # @param height [Integer] block height
      # @return [Boolean] true if the root matches the block at the given height
      # @raise [RuntimeError] when no provider is configured
      # @raise [RuntimeError] on network or API error
      def valid_root_for_height?(root, height)
        raise 'ChainTracker requires a provider when used directly' if @provider.nil?

        result = @provider.call(:get_block_header, height)
        return false if result.http_not_found?
        raise result.error_message.to_s unless result.http_success?

        actual = result.data.is_a?(Hash) ? result.data['merkle_root'] : nil
        return false unless actual

        actual.casecmp(root).zero?
      end

      # Return the current blockchain height.
      #
      # Dispatches +:current_height+ to the configured provider.
      #
      # @return [Integer] the height of the chain tip
      # @raise [RuntimeError] when no provider is configured
      # @raise [RuntimeError] on network or API error
      def current_height
        raise 'ChainTracker requires a provider when used directly' if @provider.nil?

        result = @provider.call(:current_height)
        return result.data if result.http_success?

        raise result.error_message.to_s
      end
    end
  end
end
