# frozen_string_literal: true

module BSV
  module Wallet
    # Storage implementations. See {Interface::Store} for the contract.
    module Store
      autoload :Memory, 'bsv/wallet/store/memory'
      autoload :File,   'bsv/wallet/store/file'
    end
  end
end
