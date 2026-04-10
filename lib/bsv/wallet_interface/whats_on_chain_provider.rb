# frozen_string_literal: true

module BSV
  module Wallet
    # ChainProvider implementation backed by the WhatsOnChain public API.
    #
    # Delegates to {BSV::Network::WhatsOnChain} for all HTTP communication,
    # adapting its responses to the {ChainProvider} contract.
    #
    # @example Use with WalletClient
    #   provider = BSV::Wallet::WhatsOnChainProvider.new(network: :main)
    #   wallet = BSV::Wallet::WalletClient.new(key, chain_provider: provider)
    #   wallet.sync_utxos
    class WhatsOnChainProvider
      include ChainProvider

      # @param network [Symbol] :main (default) or :test
      # @param http_client [#request, nil] injectable HTTP client for testing
      def initialize(network: :main, http_client: nil)
        woc_network = network == :main ? :mainnet : :testnet
        @woc = BSV::Network::WhatsOnChain.new(network: woc_network, http_client: http_client)
      end

      # Returns the current blockchain height.
      # @return [Integer]
      def get_height
        raise NotImplementedError, 'WhatsOnChainProvider#get_height not yet implemented'
      end

      # Returns the block header at the given height.
      # @param _height [Integer] block height
      # @return [String] 80-byte hex-encoded block header
      def get_header(_height)
        raise NotImplementedError, 'WhatsOnChainProvider#get_header not yet implemented'
      end

      # Returns unspent transaction outputs for the given address.
      #
      # Delegates to {BSV::Network::WhatsOnChain#fetch_utxos} and normalises
      # the result to plain hashes matching the ChainProvider contract.
      #
      # @param address [String] BSV address
      # @return [Array<Hash>] array of hashes with :tx_hash, :tx_pos, :value keys
      def get_utxos(address)
        @woc.fetch_utxos(address).map do |utxo|
          { tx_hash: utxo.tx_hash, tx_pos: utxo.tx_pos, value: utxo.satoshis }
        end
      end

      # Returns the raw transaction hex for the given txid.
      #
      # Delegates to {BSV::Network::WhatsOnChain#fetch_transaction} and
      # serialises the result back to hex.
      #
      # @param txid [String] transaction ID (hex)
      # @return [String] raw transaction hex string
      def get_transaction(txid)
        @woc.fetch_transaction(txid).to_hex
      end
    end
  end
end
