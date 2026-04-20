# frozen_string_literal: true

module BSV
  module Wallet
    # BRC-100 abstract contract modules.
    #
    # Provides granular sub-modules for each group of BRC-100 wallet methods.
    # Use {BRC100::Interface} to compose all 28 methods at once, or include
    # individual sub-modules to implement only a subset.
    module BRC100
      autoload :Transaction,    'bsv/wallet/interface/brc100/transaction'
      autoload :KeyManagement,  'bsv/wallet/interface/brc100/key_management'
      autoload :Crypto,         'bsv/wallet/interface/brc100/crypto'
      autoload :Identity,       'bsv/wallet/interface/brc100/identity'
      autoload :Authentication, 'bsv/wallet/interface/brc100/authentication'
      autoload :Network,        'bsv/wallet/interface/brc100/network'
      autoload :Interface,      'bsv/wallet/interface/brc100/interface'
    end
  end
end
