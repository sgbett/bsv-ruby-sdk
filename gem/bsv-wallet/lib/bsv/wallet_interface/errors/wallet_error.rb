# frozen_string_literal: true

module BSV
  module Wallet
    class WalletError < StandardError
      attr_reader :code

      def initialize(message, code = 1)
        @code = code
        super(message)
      end
    end
  end
end
