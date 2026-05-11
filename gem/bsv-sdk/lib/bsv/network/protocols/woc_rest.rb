# frozen_string_literal: true

require 'json'

module BSV
  module Network
    module Protocols
      # WoCREST implements the WhatsOnChain REST API as a Protocol subclass.
      #
      # Provides endpoints covering chain info, block headers, transactions,
      # UTXOs, scripts, address queries, broadcast, search, stats, and health.
      # Escape hatches handle WoC-specific body formats and field remapping.
      #
      # == Network resolution
      #
      # WoC uses +main+ and +test+ in its URL paths. The constructor accepts
      # symbolic aliases (:mainnet, :testnet, :stn) and resolves them to the
      # correct string.
      #
      # == Usage
      #
      #   woc = BSV::Network::Protocols::WoCREST.new(network: :main)
      #   result = woc.call(:get_tx, 'abc123...')
      #   puts result.data if result.http_success?
      #
      # @see https://developers.whatsonchain.com/ WhatsOnChain API documentation
      class WoCREST < Protocol
        NETWORKS = {
          'main' => 'main',
          'test' => 'test',
          'stn' => 'stn',
          main: 'main',
          test: 'test',
          stn: 'stn',
          mainnet: 'main',
          testnet: 'test'
        }.freeze

        # Chain
        endpoint :current_height,   :get, '/chain/info',
                 response: ->(body) { JSON.parse(body)['blocks'] }
        endpoint :get_chain_info,    :get, '/chain/info', response: :json
        endpoint :get_block_header,  :get, '/block/{height}/header', response: :json
        endpoint :get_block_headers, :get, '/block/headers', response: :json_array
        endpoint :get_circulating_supply, :get, '/circulatingsupply'
        endpoint :get_chain_tips,         :get, '/chain/tips', response: :json_array
        endpoint :get_peer_info,          :get, '/peer/info',  response: :json_array

        # Transaction
        endpoint :get_tx,            :get,  '/tx/{txid}/hex'
        endpoint :get_tx_details,    :get,  '/tx/hash/{txid}', response: :json
        endpoint :get_output_script, :get,  '/tx/{txid}/out/{index}/hex'
        endpoint :get_opreturn,      :get,  '/tx/{txid}/opreturn', response: :json
        endpoint :get_merkle_path,   :get,  '/tx/{txid}/proof/tsc', response: :json
        endpoint :broadcast,         :post, '/tx/raw'
        endpoint :decode_tx,         :post, '/tx/decode', response: :json
        endpoint :get_tx_status,     :post, '/txs/status', response: :json
        endpoint :get_tx_hex_bulk,   :post, '/txs/hex', response: :json
        endpoint :get_tx_binary,          :get,  '/tx/{txid}/bin'
        endpoint :get_tx_by_block_index,  :get,  '/block/height/{height}/txindex/{txindex}', response: :json
        endpoint :get_tx_propagation,     :get,  '/tx/hash/{txid}/propagation', response: :json
        endpoint :get_bulk_tx_details,    :post, '/txs', response: :json
        endpoint :get_bulk_output_scripts, :post, '/txs/vouts/hex', response: :json

        # UTXO / spent status
        endpoint :get_utxos,        :get,  '/address/{address}/confirmed/unspent',
                 response: :json_array
        endpoint :get_utxos_all,    :get,  '/address/{address}/unspent/all',
                 response: :json_array
        endpoint :is_utxo,          :get,  '/tx/{txid}/{vout}/spent', response: :json
        endpoint :is_utxo_bulk,     :post, '/utxos/spent', response: :json_array
        endpoint :valid_root,       :get,  '/block/{height}/header', response: :json
        endpoint :get_unconfirmed_utxos,  :get,  '/address/{address}/unconfirmed/unspent',
                 response: :json_array
        endpoint :get_confirmed_spent,    :get,  '/tx/{txid}/{vout}/confirmed/spent', response: :json
        endpoint :get_unconfirmed_spent,  :get,  '/tx/{txid}/{vout}/unconfirmed/spent', response: :json
        endpoint :get_bulk_address_utxos, :post, '/addresses/confirmed/unspent', response: :json
        endpoint :get_bulk_address_unconfirmed_utxos, :post, '/addresses/unconfirmed/unspent', response: :json

        # Script
        endpoint :get_script_unspent,     :get,  '/script/{script_hash}/confirmed/unspent',
                 response: :json_array
        endpoint :get_script_history,     :get,  '/script/{script_hash}/confirmed/history',
                 response: :json_array
        endpoint :get_script_all_unspent, :get,  '/script/{script_hash}/unspent/all',
                 response: :json_array
        endpoint :get_script_unspent_bulk, :post, '/scripts/confirmed/unspent', response: :json
        endpoint :get_script_unconfirmed_unspent, :get, '/script/{script_hash}/unconfirmed/unspent',
                 response: :json_array
        endpoint :get_bulk_script_unconfirmed_unspent, :post, '/scripts/unconfirmed/unspent', response: :json

        # Address balance / history
        endpoint :get_balance,             :get, '/address/{address}/confirmed/balance',
                 response: :json
        endpoint :get_unconfirmed_balance, :get, '/address/{address}/unconfirmed/balance',
                 response: :json
        endpoint :get_history,             :get, '/address/{address}/confirmed/history',
                 response: :json_array
        endpoint :is_address_used,         :get, '/address/{address}/used', response: :json

        # Exchange rate / fees / mempool
        endpoint :get_exchange_rate,      :get, '/exchangerate',      response: :json
        endpoint :get_fee_recommendation, :get, '/feerecommendation', response: :json
        endpoint :get_mempool_info,       :get, '/mempool/info',      response: :json
        endpoint :get_exchange_rate_historical, :get, '/exchangerate/historical', response: :json_array
        endpoint :get_mempool_raw,              :get, '/mempool/raw', response: :json_array

        # Search
        endpoint :search_links, :post, '/search/links', response: :json

        # Stats
        endpoint :get_block_stats,          :get, '/block/height/{height}/stats', response: :json
        endpoint :get_block_stats_by_hash,  :get, '/block/hash/{hash}/stats', response: :json
        endpoint :get_miner_block_stats,    :get, '/miner/blocks/stats', response: :json
        endpoint :get_miner_fees,           :get, '/miner/fees', response: :json
        endpoint :get_miner_summary,        :get, '/miner/summary/stats', response: :json
        endpoint :get_block_tag_count,      :get, '/block/tagcount/height/{height}/stats', response: :json

        # Health
        endpoint :health, :get, '/woc'

        attr_reader :network_name

        # @param base_url    [String] base URL for the WoC API; may contain
        #   +{network}+ which will be interpolated with the resolved network name
        # @param network     [Symbol, String] :main, :mainnet, :test, :testnet, :stn
        # @param api_key     [String, nil] legacy API key — sends +Authorization: key+
        #   (no Bearer prefix, matching WoC's expected auth format)
        # @param auth        [Hash, Symbol, nil] auth config hash forwarded to Protocol;
        #   when provided, takes precedence over +api_key:+
        # @param http_client [Object, nil] injectable HTTP client for testing
        def initialize(base_url:, network: :main, api_key: nil, auth: nil, http_client: nil)
          @network_name = resolve_network(network)
          # Translate legacy api_key: to auth: { api_key: } so the base class sends
          # the raw key without a Bearer prefix, matching WoC's expected auth format.
          resolved_auth = auth || (api_key ? { api_key: api_key } : nil)
          super(
            base_url: base_url,
            auth: resolved_auth,
            network: @network_name,
            http_client: http_client
          )
        end

        private

        # Resolves network aliases to the WoC URL segment string.
        #
        # @param network [Symbol, String]
        # @return [String] 'main', 'test', or 'stn'
        # @raise [ArgumentError] when the network value is not recognised
        def resolve_network(network)
          NETWORKS.fetch(network) do
            raise ArgumentError, "unknown network: #{network.inspect}"
          end
        end

        # Checks whether a specific output is unspent by querying the WoC
        # spent-status endpoint.
        #
        # WoC returns 200 with spending transaction details when an output
        # has been spent, or 404 when the output is unspent (no spending
        # transaction found). This escape hatch maps both cases to a
        # boolean: +true+ = unspent, +false+ = spent.
        #
        # The +script_hash:+ keyword is accepted for future fallback support
        # but not used in this implementation.
        #
        # @param txid        [String]  WoC API boundary: display-order hex transaction ID
        # @param vout        [Integer] output index
        # @param script_hash [String, nil] ignored
        # @return [ProtocolResponse<Boolean>]
        def call_is_utxo(txid, vout, script_hash: nil) # rubocop:disable Lint/UnusedMethodArgument
          result = default_call(:is_utxo, txid, vout)

          # 404 = no spending tx found = output is unspent
          return result.with(data: true, http_success: true, error_message: nil) if result.http_not_found?

          # Non-success, non-404 = genuine error
          return result unless result.http_success?

          # 200 with spending tx details = output is spent
          result.with(data: false)
        end

        # Bulk-checks whether a set of outputs are unspent.
        #
        # WoC expects +{ "utxos": [{ "txid": "...", "vout": N }, ...] }+ as the
        # request body. It returns an array of entries, each with:
        #   +{ "utxo": { "txid": "...", "vout": N }, "spentIn": {...} | nil, "error": "" }+
        # When +spentIn+ is present and non-empty the output is spent.
        # Entries absent from the response (unknown outputs) are treated as spent.
        #
        # @param outpoints [Array<Hash>] array of +{ txid:, vout: }+ hashes
        # @return [ProtocolResponse<Hash{String => Boolean}>]
        #   On success, data is a hash mapping +"txid.vout"+ keys to booleans
        #   (+true+ = unspent, +false+ = spent).
        def call_is_utxo_bulk(outpoints)
          return ProtocolResponse.new(nil, data: {}, http_success: true) if outpoints.empty?

          body = JSON.generate(utxos: outpoints.map { |op| { 'txid' => op[:txid].to_s, 'vout' => op[:vout].to_i } })
          result = default_call(:is_utxo_bulk, body: body)
          return result unless result.http_success?

          # Build a lookup from the response entries
          # spentIn present and non-empty → spent (false); absent or empty → unspent (true)
          normalised = result.data.each_with_object({}) do |entry, h|
            next unless entry.is_a?(Hash) && entry.key?('utxo')

            utxo = entry['utxo']
            key = "#{utxo['txid']}.#{utxo['vout']}"
            spent_in = entry['spentIn']
            h[key] = spent_in.nil? || !spent_in.is_a?(Hash) || spent_in.empty?
          end

          # Unknown outpoints (absent from response) default to spent (false)
          outpoints.each do |op|
            key = "#{op[:txid]}.#{op[:vout]}"
            normalised[key] = false unless normalised.key?(key)
          end

          result.with(data: normalised)
        end

        # Broadcasts a raw transaction to WhatsOnChain.
        #
        # WoC expects the body as +{ txhex: "..." }+ (JSON). On success it
        # returns the txid as a plain-text string (not JSON). The response is
        # stripped and wrapped in a Hash for caller convenience.
        #
        # @param tx [#to_hex, String] transaction object or raw hex string
        # @return [ProtocolResponse<{ txid: String }>]
        def call_broadcast(tx)
          hex  = tx.respond_to?(:to_hex) ? tx.to_hex : tx.to_s
          body = JSON.generate(txhex: hex)

          result = default_call(:broadcast, body: body)
          return result unless result.http_success?

          # WoC returns plain-text txid — result.data is the raw body string
          # WoC API boundary: display-order hex txid returned as plain text
          result.with(data: { txid: result.data.to_s.strip })
        end

        # Decodes a raw transaction hex by posting to the WoC decode endpoint.
        #
        # WoC expects the body as +{ txhex: "..." }+ (JSON) and returns a
        # full decoded transaction object.
        #
        # @param txhex [String] raw transaction hex string
        # @return [ProtocolResponse]
        def call_decode_tx(txhex)
          body = JSON.generate(txhex: txhex.to_s)
          default_call(:decode_tx, body: body)
        end

        # Fetches raw hex for multiple transactions in a single request.
        #
        # WoC expects +{ "txids": [...] }+ as the request body.
        #
        # @param txids [Array<String>] list of transaction IDs
        # @return [ProtocolResponse]
        def call_get_tx_hex_bulk(txids)
          body = JSON.generate(txids: txids)
          default_call(:get_tx_hex_bulk, body: body)
        end

        # Fetches confirmed UTXOs for multiple script hashes in a single request.
        #
        # WoC expects +{ "scripts": [...] }+ as the request body.
        #
        # @param script_hashes [Array<String>] list of script hashes
        # @return [ProtocolResponse]
        def call_get_script_unspent_bulk(script_hashes)
          body = JSON.generate(scripts: script_hashes)
          default_call(:get_script_unspent_bulk, body: body)
        end

        # Fetches full transaction details for multiple transactions.
        #
        # WoC expects +{ "txids": [...] }+ as the request body.
        #
        # @param txids [Array<String>] list of transaction IDs
        # @return [ProtocolResponse]
        def call_get_bulk_tx_details(txids)
          body = JSON.generate(txids: txids)
          default_call(:get_bulk_tx_details, body: body)
        end

        # Fetches output scripts for specific vouts across multiple transactions.
        #
        # WoC expects +{ "txids": [{ "txid": "...", "vouts": [0, 1] }, ...] }+ as the request body.
        #
        # @param tx_vouts [Array<Hash>] array of +{ txid:, vouts: [Integer] }+ hashes
        # @return [ProtocolResponse]
        def call_get_bulk_output_scripts(tx_vouts)
          body = JSON.generate(txids: tx_vouts.map { |tv| { 'txid' => tv[:txid].to_s, 'vouts' => tv[:vouts] } })
          default_call(:get_bulk_output_scripts, body: body)
        end

        # Fetches confirmed UTXOs for multiple addresses in a single request.
        #
        # WoC expects +{ "addresses": [...] }+ as the request body.
        #
        # @param addresses [Array<String>] list of addresses
        # @return [ProtocolResponse]
        def call_get_bulk_address_utxos(addresses)
          body = JSON.generate(addresses: addresses)
          default_call(:get_bulk_address_utxos, body: body)
        end

        # Fetches unconfirmed UTXOs for multiple addresses in a single request.
        #
        # WoC expects +{ "addresses": [...] }+ as the request body.
        #
        # @param addresses [Array<String>] list of addresses
        # @return [ProtocolResponse]
        def call_get_bulk_address_unconfirmed_utxos(addresses)
          body = JSON.generate(addresses: addresses)
          default_call(:get_bulk_address_unconfirmed_utxos, body: body)
        end

        # Fetches unconfirmed UTXOs for multiple script hashes in a single request.
        #
        # WoC expects +{ "scripts": [...] }+ as the request body.
        #
        # @param script_hashes [Array<String>] list of script hashes
        # @return [ProtocolResponse]
        def call_get_bulk_script_unconfirmed_unspent(script_hashes)
          body = JSON.generate(scripts: script_hashes)
          default_call(:get_bulk_script_unconfirmed_unspent, body: body)
        end

        # Searches WhatsOnChain for links matching a query.
        #
        # WoC expects +{ "query": "..." }+ as the request body.
        #
        # @param query [String] search term
        # @return [ProtocolResponse]
        def call_search_links(query)
          body = JSON.generate(query: query)
          default_call(:search_links, body: body)
        end

        # Fetches status for multiple transactions.
        #
        # WoC expects +{ "txids": [...] }+ as the request body. When called
        # with a raw +body:+ keyword the body is forwarded as-is, which
        # preserves backwards-compatibility with callers that build the body
        # themselves.
        #
        # @param txids [Array<String>, nil] list of transaction IDs (positional)
        # @param body  [String, nil] pre-serialised request body (keyword)
        # @return [ProtocolResponse]
        # @raise [ArgumentError] when neither txids nor body is provided
        def call_get_tx_status(txids = nil, body: nil)
          raise ArgumentError, 'provide txids array or body: keyword' if txids.nil? && body.nil?

          raw_body = body || JSON.generate(txids: txids)
          default_call(:get_tx_status, body: raw_body)
        end

        # Verifies that a merkle root matches the one recorded for a given
        # block height. Uses the get_block_header endpoint internally.
        #
        # Comparison is case-insensitive to tolerate mixed-case hex from
        # different providers.
        #
        # @param root   [String]  expected merkle root as hex
        # @param height [Integer] block height
        # @return [ProtocolResponse<Boolean>]
        def call_valid_root(root, height)
          result = default_call(:valid_root, height)
          return result unless result.http_success?

          actual = result.data['merkleroot']
          result.with(data: actual.to_s.downcase == root.to_s.downcase)
        end
      end
    end
  end
end
