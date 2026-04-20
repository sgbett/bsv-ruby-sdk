# frozen_string_literal: true

module BSV
  module Wallet
    module Interface
      # Duck-typed interface for merkle proof persistence.
      #
      # Include this module in proof store implementations and override all
      # methods. The default implementations raise NotImplementedError.
      module ProofStore
        def store_proof(_txid, _merkle_path)
          raise NotImplementedError, "#{self.class}#store_proof not implemented"
        end

        def resolve_proof(_txid)
          raise NotImplementedError, "#{self.class}#resolve_proof not implemented"
        end
      end
    end
  end
end
