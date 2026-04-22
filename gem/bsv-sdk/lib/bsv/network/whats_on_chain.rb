# frozen_string_literal: true

module BSV
  module Network
    # WhatsOnChain chain data provider for reading transactions and UTXOs
    # from the BSV network.
    #
    # Any object responding to #fetch_utxos(address),
    # #fetch_transaction(txid), #current_height,
    # #get_block_header(height), and optionally
    # #valid_root_for_height?(root_hex, height) can serve as a chain
    # data source;
    # this class implements that contract by delegating to
    # Protocols::WoCREST.
    #
    # The HTTP client is injectable for testability. It must respond to
    # #request(uri, request) and return an object with #code and #body.
    class WhatsOnChain
      # Returns a WhatsOnChain instance using the provider default.
      #
      # @param testnet [Boolean] when true, uses the testnet endpoint
      # @param opts [Hash] forwarded to the underlying protocol (e.g. +api_key:+, +http_client:+)
      # @return [WhatsOnChain]
      def self.default(testnet: false, **opts)
        provider = Providers::WhatsOnChain.default(testnet: testnet, **opts)
        new(protocol: provider.protocol_for(:get_tx))
      end

      # @param network [Symbol] :main, :mainnet, :test, :testnet, :stn (legacy compat)
      # @param http_client [#request, nil] injectable HTTP client
      # @param protocol [BSV::Network::Protocols::WoCREST, nil] pre-configured protocol
      def initialize(network: :mainnet, http_client: nil, protocol: nil)
        if protocol
          @protocol = protocol
        else
          provider = Providers::WhatsOnChain.default(network: network, http_client: http_client)
          @protocol = provider.protocol_for(:get_tx)
        end
      end

      # Fetch unspent transaction outputs for an address.
      # @param address [String] BSV address
      # @return [Array<UTXO>]
      def fetch_utxos(address)
        result = @protocol.call(:get_utxos_all, address)
        raise_on_error(result)

        result.data.map do |entry|
          UTXO.new(
            tx_hash: entry[:tx_hash],
            tx_pos: entry[:tx_pos],
            satoshis: entry[:satoshis],
            height: entry[:height]
          )
        end
      end

      # Fetch a raw transaction by its txid and parse it.
      # @param txid [String] transaction ID (hex)
      # @return [BSV::Transaction::Transaction]
      def fetch_transaction(txid)
        result = @protocol.call(:get_tx, txid)
        raise_on_error(result)

        BSV::Transaction::Transaction.from_hex(result.data)
      end

      # Return the current blockchain height.
      # @return [Integer]
      # @raise [BSV::Network::ChainProviderError] on network or API error
      def current_height
        result = @protocol.call(:current_height)
        raise_on_error(result)

        result.data
      end

      # Fetch the block header for a given height.
      # @param height [Integer] block height
      # @return [Hash] parsed block header JSON
      # @raise [BSV::Network::ChainProviderError] on network or API error
      def get_block_header(height)
        result = @protocol.call(:get_block_header, height)
        raise_on_error(result)

        result.data
      end

      # Verify that a merkle root is valid for the given block height.
      # @param root [String] expected merkle root as hex
      # @param height [Integer] block height
      # @return [Boolean]
      # @raise [BSV::Network::ChainProviderError] on network or API error
      def valid_root_for_height?(root, height)
        result = @protocol.call(:valid_root, root, height)
        return false if result.not_found?

        raise_on_error(result)

        result.data == true
      end

      private

      # Translates a non-success Protocol result into a raised ChainProviderError.
      #
      # @param result [Result::Error, Result::NotFound]
      # @raise [ChainProviderError]
      def raise_on_error(result)
        return if result.success?

        raise ChainProviderError.new(
          result.message || 'Request failed',
          status_code: result.metadata[:status_code]
        )
      end
    end
  end
end
