# frozen_string_literal: true

module BSV
  module Wallet
    # Abstract binary transport for BRC-103 wallet communication.
    #
    # Include this module and implement {#transmit_to_wallet} to provide a
    # concrete transport (e.g. HTTP, in-process loopback, Unix socket).
    module WalletWire
      # Transmit a binary request frame to the wallet and return the binary result frame.
      #
      # @param message [String] binary request frame (ASCII-8BIT)
      # @return [String] binary result frame (ASCII-8BIT)
      # @raise [NotImplementedError] unless overridden by the including class
      def transmit_to_wallet(message)
        raise NotImplementedError, "#{self.class}#transmit_to_wallet is not implemented"
      end
    end
  end
end
