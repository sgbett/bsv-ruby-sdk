# frozen_string_literal: true

module BSV
  module Transaction
    # Namespace for chain tracker implementations.
    module ChainTrackers
      autoload :WhatsOnChain, 'bsv/transaction/chain_trackers/whats_on_chain'
      autoload :Chaintracks,  'bsv/transaction/chain_trackers/chaintracks'

      # Return a default chain tracker backed by the Arcade/GorillaPool Chaintracks API.
      #
      # @param testnet [Boolean] use the testnet endpoint when true
      # @param opts [Hash] forwarded to the underlying tracker (e.g. +api_key:+)
      # @return [Chaintracks]
      def self.default(testnet: false, **opts)
        Chaintracks.default(testnet: testnet, **opts)
      end
    end
  end
end
