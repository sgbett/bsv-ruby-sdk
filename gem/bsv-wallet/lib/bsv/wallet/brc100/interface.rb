# frozen_string_literal: true

module BSV
  module Wallet
    module BRC100
      # Composed BRC-100 interface — includes all 6 sub-modules.
      #
      # A class that includes this module responds to all 28 BRC-100 methods.
      # Each method raises {BSV::Wallet::UnsupportedActionError} by default;
      # override only the methods your implementation supports.
      #
      # @example
      #   class MyWallet
      #     include BSV::Wallet::BRC100::Interface
      #
      #     def get_height(args = {}, originator: nil)
      #       { height: 800_000 }
      #     end
      #   end
      module Interface
        include Transaction
        include KeyManagement
        include Crypto
        include Identity
        include Authentication
        include Network
      end
    end
  end
end
