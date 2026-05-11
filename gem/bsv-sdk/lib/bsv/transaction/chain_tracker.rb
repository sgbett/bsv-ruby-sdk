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
    # The SDK is deliberately unopinionated about where that answer comes
    # from. A chain tracker backed by an in-memory hash is declarative.
    # One that fetches from the network on cache miss and writes to a
    # database is imperative. The verify methods don't care — they just
    # ask the question. All imperative behaviour (fetching, caching,
    # persisting) lives in the consumer's chain tracker implementation,
    # not in the SDK.
    #
    # Any object responding to +valid_root_for_height?+ and
    # +current_height+ satisfies this interface. Inheriting from this
    # class is optional — it exists to document the contract and provide
    # clear error messages when methods are missing.
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
    class ChainTracker
      # Verify that a merkle root is valid for the given block height.
      #
      # @param root [String] merkle root as a hex string
      # @param height [Integer] block height
      # @return [Boolean] true if the root matches the block at the given height
      # @raise [NotImplementedError] if not overridden by a subclass
      def valid_root_for_height?(_root, _height)
        raise NotImplementedError, "#{self.class}#valid_root_for_height? must be implemented"
      end

      # Return the current blockchain height.
      #
      # @return [Integer] the height of the chain tip
      # @raise [NotImplementedError] if not overridden by a subclass
      def current_height
        raise NotImplementedError, "#{self.class}#current_height must be implemented"
      end
    end
  end
end
