# frozen_string_literal: true

module BSV
  module Wallet
    class InvalidSignatureError < WalletError
      def initialize(message = 'The provided signature is invalid')
        super(message, 4)
      end
    end
  end
end
