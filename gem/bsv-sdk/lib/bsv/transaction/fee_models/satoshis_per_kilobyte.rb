# frozen_string_literal: true

module BSV
  module Transaction
    module FeeModels
      # Fee model that charges a configurable number of satoshis per kilobyte.
      #
      # Uses the transaction's estimated size (from templates for unsigned inputs,
      # actual size for signed inputs) to compute the fee.
      #
      # @example
      #   model = BSV::Transaction::FeeModels::SatoshisPerKilobyte.new(value: 100)
      #   fee = model.compute_fee(transaction) # => 25 (for a ~250 byte tx)
      class SatoshisPerKilobyte < FeeModel
        # @return [Integer] satoshis per kilobyte rate
        attr_reader :value

        # @param value [Integer] satoshis per kilobyte (default: 100)
        def initialize(value: 100)
          super()
          @value = value
        end

        # Compute the fee for a transaction based on its estimated size.
        #
        # @param transaction [Transaction] the transaction to compute the fee for
        # @return [Integer] the fee in satoshis
        def compute_fee(transaction)
          size = transaction.estimated_size
          (size / 1000.0 * @value).ceil
        end
      end
    end
  end
end
