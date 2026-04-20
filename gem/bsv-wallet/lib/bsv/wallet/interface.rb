# frozen_string_literal: true

module BSV
  module Wallet
    # Abstract interfaces (contracts) for the wallet ecosystem.
    #
    # Each module under Interface defines what an implementation must do,
    # not how. Include the relevant interface in your concrete class.
    module Interface
      autoload :BRC100,         'bsv/wallet/interface/brc100'
      autoload :Store,          'bsv/wallet/interface/store'
      autoload :BroadcastQueue, 'bsv/wallet/interface/broadcast_queue'
      autoload :ProofStore,     'bsv/wallet/interface/proof_store'
      autoload :UTXOPool,       'bsv/wallet/interface/utxo_pool'
    end
  end
end
