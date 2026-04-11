# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module BSV
  module Network
    # WhatsOnChain chain data provider for reading transactions and UTXOs
    # from the BSV network.
    #
    # Any object responding to #fetch_utxos(address) and
    # #fetch_transaction(txid) can serve as a chain data provider;
    # this class implements that contract using the WhatsOnChain API.
    #
    # The HTTP client is injectable for testability. It must respond to
    # #request(uri, request) and return an object with #code and #body.
    class WhatsOnChain
      BASE_URL = 'https://api.whatsonchain.com'

      def initialize(network: :mainnet, http_client: nil)
        @network = network == :mainnet ? 'main' : 'test'
        @http_client = http_client
      end

      # Fetch unspent transaction outputs for an address.
      # @param address [String] BSV address
      # @return [Array<UTXO>]
      def fetch_utxos(address)
        response = get("/v1/bsv/#{@network}/address/#{address}/unspent")
        body = JSON.parse(response.body)

        body.map do |entry|
          UTXO.new(
            tx_hash: entry['tx_hash'],
            tx_pos: entry['tx_pos'],
            satoshis: entry['value'],
            height: entry['height']
          )
        end
      end

      # Fetch a raw transaction by its txid and parse it.
      # @param txid [String] transaction ID (hex)
      # @return [BSV::Transaction::Transaction]
      def fetch_transaction(txid)
        response = get("/v1/bsv/#{@network}/tx/#{txid}/hex")
        BSV::Transaction::Transaction.from_hex(response.body)
      end

      private

      def get(path)
        uri = URI("#{BASE_URL}#{path}")
        request = Net::HTTP::Get.new(uri)
        response = execute(uri, request)
        handle_response(response)
        response
      end

      def execute(uri, request)
        if @http_client
          @http_client.request(uri, request)
        else
          Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
            http.request(request)
          end
        end
      end

      def handle_response(response)
        code = response.code.to_i
        return if (200..299).cover?(code)

        raise ChainProviderError.new(
          response.body || "HTTP #{code}",
          status_code: code
        )
      end
    end
  end
end
