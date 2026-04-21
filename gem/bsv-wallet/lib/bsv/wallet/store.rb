# frozen_string_literal: true

module BSV
  module Wallet
    # Storage implementations. See {Interface::Store} for the contract.
    #
    # The recommended adapter is {Store::File} (JSON file-backed) or
    # +bsv-wallet-postgres+ for production use.
    #
    # {Store::Memory} is available but will raise when passed to
    # +Client.new+ unless +allow_memory_store: true+ is set — data is
    # lost on process exit, including derived key material needed to
    # spend change outputs.
    module Store
      autoload :Memory, 'bsv/wallet/store/memory'
      autoload :File,   'bsv/wallet/store/file'
    end
  end
end
