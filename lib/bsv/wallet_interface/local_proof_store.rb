# frozen_string_literal: true

module BSV
  module Wallet
    # Default proof store — persists serialised merkle proofs via a
    # {StorageAdapter}. Requires no external services.
    #
    # @example Using the default local proof store
    #   store   = BSV::Wallet::MemoryStore.new
    #   proofs  = BSV::Wallet::LocalProofStore.new(store)
    #   proofs.store_proof(txid_hex, merkle_path)
    #   proof   = proofs.resolve_proof(txid_hex)
    class LocalProofStore
      include ProofStore

      # @param storage [StorageAdapter] the underlying persistence adapter
      def initialize(storage)
        @storage = storage
      end

      # Serialise and store a merkle proof.
      #
      # @param txid [String] hex transaction ID
      # @param merkle_path [BSV::Transaction::MerklePath] the proof to store
      # @return [void]
      def store_proof(txid, merkle_path)
        @storage.store_proof(txid, merkle_path.to_hex)
      end

      # Resolve and deserialise a merkle proof.
      #
      # @param txid [String] hex transaction ID
      # @return [BSV::Transaction::MerklePath, nil] the proof, or nil if unknown
      def resolve_proof(txid)
        bump_hex = @storage.find_proof(txid)
        return unless bump_hex

        BSV::Transaction::MerklePath.from_hex(bump_hex)
      end
    end
  end
end
