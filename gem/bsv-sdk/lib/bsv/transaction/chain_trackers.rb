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
      # @param api_key [String, nil] optional Bearer API key
      # @return [Chaintracks]
      def self.default(testnet: false, api_key: nil)
        url = testnet ? Chaintracks::TESTNET_URL : Chaintracks::MAINNET_URL
        Chaintracks.new(url: url, api_key: api_key)
      end
    end
  end
end
