# frozen_string_literal: true

module BSV
  module Wallet
    class InvalidHmacError < WalletError
      def initialize(message = 'The provided HMAC is invalid')
        super(message, 3)
      end
    end
  end
end
