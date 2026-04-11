# frozen_string_literal: true

module BSV
  module Transaction
    # Base class for chain trackers that verify merkle roots against the blockchain.
    #
    # Chain trackers confirm that a given merkle root corresponds to a valid block
    # at a specific height. This is essential for SPV verification — without it,
    # merkle proofs cannot be validated against the actual blockchain.
    #
    # Subclasses must implement {#valid_root_for_height?} and {#current_height}.
    #
    # @example Implementing a custom chain tracker
    #   class MyTracker < BSV::Transaction::ChainTracker
    #     def valid_root_for_height?(root, height)
    #       # query your block header source
    #     end
    #
    #     def current_height
    #       # return current chain tip height
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
