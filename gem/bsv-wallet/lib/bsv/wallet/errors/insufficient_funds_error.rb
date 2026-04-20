# frozen_string_literal: true

module BSV
  module Wallet
    class InsufficientFundsError < StandardError
      attr_reader :required, :available

      def initialize(message = nil, required: nil, available: nil)
        @required = required
        @available = available
        super(message || "insufficient funds: need #{required}, have #{available}")
      end
    end
  end
end
