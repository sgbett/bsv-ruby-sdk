# frozen_string_literal: true

module BSV
  module Wallet
    # Shared contract: BRC-100 error classes and interface definition.
    # These are the canonical definitions consumed by both bsv-sdk (ProtoWallet)
    # and bsv-wallet (Engine).
    require_relative 'wallet/errors'
    require_relative 'wallet/interface'

    # Wire layer — BRC-103 frame codec, call enum, validators, reader/writer.
    require_relative 'wallet/wire'

    # Per-call BRC-103 serialisers and dispatch tables.
    autoload :Serializer, 'bsv/wallet/serializer'

    # ProtoWallet — minimal crypto-only BRC-100 implementation.
    # Its internals (KeyDeriver, Validators) are scoped under ProtoWallet::
    # to avoid collision with bsv-wallet's own KeyDeriver.
    require_relative 'wallet/proto_wallet'

    # BRC-103 transport layer.
    autoload :WalletWire,             'bsv/wallet/wallet_wire'
    autoload :WalletWireTransceiver,  'bsv/wallet/wallet_wire_transceiver'
    autoload :WalletWireProcessor,    'bsv/wallet/wallet_wire_processor'

    # BRC-103 transport substrates.
    module Substrates
      autoload :HTTPWalletWire, 'bsv/wallet/substrates/http_wallet_wire'
      autoload :HTTPWalletJSON, 'bsv/wallet/substrates/http_wallet_json'
    end
  end
end
