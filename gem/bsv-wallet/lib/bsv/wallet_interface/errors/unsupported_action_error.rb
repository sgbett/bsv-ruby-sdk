# frozen_string_literal: true

module BSV
  module Wallet
    class UnsupportedActionError < WalletError
      def initialize(method_name = 'this method')
        super("#{method_name} is not supported by this wallet implementation", 2)
      end
    end
  end
end
