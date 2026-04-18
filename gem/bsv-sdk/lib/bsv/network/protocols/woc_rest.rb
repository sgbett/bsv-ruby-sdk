# frozen_string_literal: true

require 'json'

module BSV
  module Network
    module Protocols
      # WoCREST implements the WhatsOnChain REST API as a Protocol subclass.
      #
      # Provides 30 endpoints covering chain info, block headers, transactions,
      # UTXOs, scripts, address queries, broadcast, and health. Seven escape hatches
      # handle WoC-specific body formats and field remapping.
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
      #   puts result.data if result.success?
      class WoCREST < Protocol
        BASE_URL = 'https://api.whatsonchain.com/v1/bsv/{network}'

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

        # UTXO / spent status
        endpoint :get_utxos,        :get,  '/address/{address}/confirmed/unspent',
                 response: :json_array
        endpoint :get_utxos_all,    :get,  '/address/{address}/unspent',
                 response: :json_array
        endpoint :is_utxo,          :get,  '/tx/{txid}/{vout}/spent', response: :json
        endpoint :is_utxo_bulk,     :post, '/utxos/spent', response: :json_array
        endpoint :valid_root,       :get,  '/block/{height}/header', response: :json

        # Script
        endpoint :get_script_unspent,     :get,  '/script/{script_hash}/confirmed/unspent',
                 response: :json_array
        endpoint :get_script_history,     :get,  '/script/{script_hash}/confirmed/history',
                 response: :json_array
        endpoint :get_script_all_unspent, :get,  '/script/{script_hash}/unspent/all',
                 response: :json_array
        endpoint :get_script_unspent_bulk, :post, '/scripts/confirmed/unspent', response: :json

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

        # Health
        endpoint :health, :get, '/health'

        attr_reader :network_name

        # @param base_url    [String, nil] override the default base URL; may contain
        #   +{network}+ which will be interpolated with the resolved network name
        # @param network  [Symbol, String] :main, :mainnet, :test, :testnet, :stn
        # @param api_key  [String, nil]    optional Bearer API key
        # @param http_client [Object, nil] injectable HTTP client for testing
        def initialize(base_url: nil, network: :main, api_key: nil, http_client: nil)
          @network_name = resolve_network(network)
          super(
            base_url: base_url || BASE_URL,
            api_key: api_key,
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

        # Fetches confirmed UTXOs for an address and remaps the +value+ field
        # to +satoshis+ to match the SDK's UTXO convention.
        #
        # WoC returns entries with +{ tx_hash, tx_pos, value, height }+;
        # callers and facades expect +satoshis+ in place of +value+.
        #
        # @param address [String] BSV address
        # @return [Result::Success, Result::Error, Result::NotFound]
        def call_get_utxos(address)
          result = default_call(:get_utxos, address)
          return result unless result.success?

          Result::Success.new(data: remap_utxo_entries(result.data))
        end

        # Fetches all UTXOs (confirmed and unconfirmed) for an address and
        # remaps the +value+ field to +satoshis+. Uses the legacy +/unspent+
        # endpoint rather than +/confirmed/unspent+.
        #
        # @param address [String] BSV address
        # @return [Result::Success, Result::Error, Result::NotFound]
        def call_get_utxos_all(address)
          result = default_call(:get_utxos_all, address)
          return result unless result.success?

          Result::Success.new(data: remap_utxo_entries(result.data))
        end

        # Remaps WoC UTXO entries from +{ 'value' => n }+ to +{ satoshis: n }+.
        #
        # @param entries [Array<Hash>]
        # @return [Array<Hash>]
        def remap_utxo_entries(entries)
          entries.map do |entry|
            {
              tx_hash: entry['tx_hash'],
              tx_pos: entry['tx_pos'],
              satoshis: entry['value'],
              height: entry['height']
            }
          end
        end

        # Checks whether a specific output is unspent by querying the WoC
        # spent-status endpoint.
        #
        # WoC returns a JSON object indicating whether the output has been spent.
        # The +script_hash:+ keyword is accepted for future fallback support
        # but not used in this implementation.
        #
        # @param txid        [String]  transaction ID
        # @param vout        [Integer] output index
        # @param script_hash [String, nil] ignored
        # @return [Result::Success<Boolean>, Result::Error, Result::NotFound]
        def call_is_utxo(txid, vout, script_hash: nil) # rubocop:disable Lint/UnusedMethodArgument
          result = default_call(:is_utxo, txid, vout)
          return result unless result.success?

          # WoC returns { "spent": true/false, ... } — unspent means NOT spent
          unless result.data.is_a?(Hash) && result.data.key?('spent')
            return Result::Error.new(message: 'missing spent field in response', retryable: false)
          end

          spent = result.data['spent']
          Result::Success.new(data: !spent)
        end

        # Bulk-checks whether a set of outputs are unspent.
        #
        # WoC expects a JSON array of +{ txid, vout }+ objects. It returns an
        # array of entries, each containing +txid+, +vout+, and +spent+ fields.
        # Entries absent from the response (unknown outputs) are treated as spent.
        #
        # @param outpoints [Array<Hash>] array of +{ txid:, vout: }+ hashes
        # @return [Result::Success<Hash{String => Boolean}>, Result::Error]
        #   On success, data is a hash mapping +"txid.vout"+ keys to booleans
        #   (+true+ = unspent, +false+ = spent).
        def call_is_utxo_bulk(outpoints)
          return Result::Success.new(data: {}) if outpoints.empty?

          body = JSON.generate(outpoints.map { |op| { 'txid' => op[:txid].to_s, 'vout' => op[:vout].to_i } })
          result = default_call(:is_utxo_bulk, body: body)
          return result unless result.success?

          # Build a lookup from the response — unknown outpoints default to spent
          spent_map = {}
          result.data.each do |entry|
            next unless entry.is_a?(Hash) && entry.key?('txid') && entry.key?('vout')

            key = "#{entry['txid']}.#{entry['vout']}"
            spent_map[key] = entry['spent']
          end

          normalised = outpoints.each_with_object({}) do |op, h|
            key = "#{op[:txid]}.#{op[:vout]}"
            h[key] = spent_map.key?(key) ? !spent_map[key] : false
          end

          Result::Success.new(data: normalised)
        end

        # Broadcasts a raw transaction to WhatsOnChain.
        #
        # WoC expects the body as +{ txhex: "..." }+ (JSON). On success it
        # returns the txid as a plain-text string (not JSON). The response is
        # stripped and wrapped in a Hash for caller convenience.
        #
        # @param tx [#to_hex, String] transaction object or raw hex string
        # @return [Result::Success<{ txid: String }>, Result::Error]
        def call_broadcast(tx)
          hex  = tx.respond_to?(:to_hex) ? tx.to_hex : tx.to_s
          body = JSON.generate(txhex: hex)

          result = default_call(:broadcast, body: body)
          return result unless result.success?

          # WoC returns plain-text txid — result.data is the raw body string
          Result::Success.new(data: { txid: result.data.to_s.strip })
        end

        # Decodes a raw transaction hex by posting to the WoC decode endpoint.
        #
        # WoC expects the body as +{ txhex: "..." }+ (JSON) and returns a
        # full decoded transaction object.
        #
        # @param txhex [String] raw transaction hex string
        # @return [Result::Success<Hash>, Result::Error]
        def call_decode_tx(txhex)
          body = JSON.generate(txhex: txhex.to_s)
          default_call(:decode_tx, body: body)
        end

        # Fetches raw hex for multiple transactions in a single request.
        #
        # WoC expects a bare JSON array of txid strings as the request body.
        #
        # @param txids [Array<String>] list of transaction IDs
        # @return [Result::Success<Array>, Result::Error]
        def call_get_tx_hex_bulk(txids)
          body = JSON.generate(txids)
          default_call(:get_tx_hex_bulk, body: body)
        end

        # Fetches confirmed UTXOs for multiple script hashes in a single request.
        #
        # WoC expects a bare JSON array of script hash strings as the request body.
        #
        # @param script_hashes [Array<String>] list of script hashes
        # @return [Result::Success<Hash>, Result::Error]
        def call_get_script_unspent_bulk(script_hashes)
          body = JSON.generate(script_hashes)
          default_call(:get_script_unspent_bulk, body: body)
        end

        # Verifies that a merkle root matches the one recorded for a given
        # block height. Uses the get_block_header endpoint internally.
        #
        # Comparison is case-insensitive to tolerate mixed-case hex from
        # different providers.
        #
        # @param root   [String]  expected merkle root as hex
        # @param height [Integer] block height
        # @return [Result::Success<Boolean>, Result::Error, Result::NotFound]
        def call_valid_root(root, height)
          result = default_call(:valid_root, height)
          return result unless result.success?

          actual = result.data['merkleroot']
          Result::Success.new(data: actual.to_s.downcase == root.to_s.downcase)
        end
      end
    end
  end
end
