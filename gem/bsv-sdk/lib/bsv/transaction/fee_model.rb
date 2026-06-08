# frozen_string_literal: true

module BSV
  module Transaction
    # Base class for fee models that compute transaction fees.
    #
    # Fee models determine how many satoshis a transaction should pay in fees
    # based on its size or other properties. Subclasses must implement
    # {#compute_fee}.
    #
    # @example Implementing a custom fee model
    #   class FixedFee < BSV::Transaction::FeeModel
    #     def compute_fee(_transaction)
    #       1000
    #     end
    #   end
    class FeeModel
      # Compute the fee for a transaction.
      #
      # @param transaction [Tx] the transaction to compute the fee for
      # @return [Integer] the fee in satoshis
      # @raise [NotImplementedError] if not overridden by a subclass
      def compute_fee(_transaction)
        raise NotImplementedError, "#{self.class}#compute_fee must be implemented"
      end
    end
  end
end
