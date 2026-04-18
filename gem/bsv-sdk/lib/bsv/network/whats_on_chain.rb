# frozen_string_literal: true

module BSV
  module Network
    # WhatsOnChain chain data provider for reading transactions and UTXOs
    # from the BSV network.
    #
    # Any object responding to #fetch_utxos(address) and
    # #fetch_transaction(txid) can serve as a chain data provider;
    # this class implements that contract by delegating to
    # Protocols::WoCREST.
    #
    # The HTTP client is injectable for testability. It must respond to
    # #request(uri, request) and return an object with #code and #body.
    class WhatsOnChain
      def initialize(network: :mainnet, http_client: nil)
        @protocol = Protocols::WoCREST.new(network: network, http_client: http_client)
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
