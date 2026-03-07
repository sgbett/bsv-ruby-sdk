# frozen_string_literal: true

module BSV
  module Transaction
    # Namespace for chain tracker implementations.
    module ChainTrackers
      autoload :WhatsOnChain, 'bsv/transaction/chain_trackers/whats_on_chain'
    end
  end
end
