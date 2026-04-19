# frozen_string_literal: true

module BSV
  module Wallet
    # Duck-typed interface for merkle proof persistence.
    #
    # Include this module in proof store implementations and override all
    # methods. The default implementations raise NotImplementedError.
    #
    # Two implementations ship with the SDK:
    # - {LocalProofStore} — persists proofs via a {StorageAdapter} (default)
    # - Future: ChaintracksProofStore — resolves proofs from an external service
    module ProofStore
      # Store a merkle proof for a transaction.
      #
      # @param _txid [String] hex transaction ID
      # @param _merkle_path [BSV::Transaction::MerklePath] the proof to store
      # @return [void]
      def store_proof(_txid, _merkle_path)
        raise NotImplementedError, "#{self.class}#store_proof not implemented"
      end

      # Resolve a merkle proof for a transaction.
      #
      # @param _txid [String] hex transaction ID
      # @return [BSV::Transaction::MerklePath, nil] the proof, or nil if unknown
      def resolve_proof(_txid)
        raise NotImplementedError, "#{self.class}#resolve_proof not implemented"
      end
    end
  end
end
