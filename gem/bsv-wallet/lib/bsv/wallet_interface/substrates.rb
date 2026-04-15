# frozen_string_literal: true

module BSV
  module Wallet
    # BRC-100 wallet substrates — alternative transport layers for the wallet interface.
    #
    # Substrates are raw transport adapters. They are not full Wallet::Interface implementations;
    # instead they provide the low-level connectivity that a WalletWireTransceiver or
    # HTTPWalletJSON wraps to expose the full interface.
    module Substrates
      autoload :HTTPWalletJSON, 'bsv/wallet_interface/substrates/http_wallet_json'
      autoload :HTTPWalletWire, 'bsv/wallet_interface/substrates/http_wallet_wire'
      autoload :WalletWireTransceiver, 'bsv/wallet_interface/substrates/wallet_wire_transceiver'
    end
  end
end
