# frozen_string_literal: true

require 'json'

module BSV
  module Network
    module Protocols
      # WoCREST implements the WhatsOnChain REST API as a Protocol subclass.
      #
      # Provides 12 endpoints covering chain info, block headers, transactions,
      # UTXOs, scripts, broadcast, and health. Three escape hatches handle
      # WoC-specific body formats and field remapping.
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
        endpoint :get_block_header, :get, '/block/{height}/header', response: :json

        # Transaction
        endpoint :get_tx,           :get,  '/tx/{txid}/hex'
        endpoint :get_merkle_path,  :get,  '/tx/{txid}/proof/tsc', response: :json
        endpoint :broadcast,        :post, '/tx/raw'
        endpoint :get_tx_status,    :post, '/txs/status', response: :json

        # UTXO / spent status
        endpoint :get_utxos,        :get,  '/address/{address}/confirmed/unspent',
                 response: :json_array
        endpoint :get_utxos_all,    :get,  '/address/{address}/unspent',
                 response: :json_array
        endpoint :is_utxo,          :get,  '/tx/{txid}/{vout}/spent', response: :json
        endpoint :valid_root,       :get,  '/block/{height}/header', response: :json

        # Script
        endpoint :get_script_unspent, :get, '/script/{script_hash}/confirmed/unspent',
                 response: :json_array

        # Address balance
        endpoint :get_balance,      :get,  '/address/{address}/confirmed/balance',
                 response: :json

        # Health
        endpoint :health,           :get,  '/health'

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
        # (Phase E) but not used in this implementation.
        #
        # @param txid        [String]  transaction ID
        # @param vout        [Integer] output index
        # @param script_hash [String, nil] ignored in Phase B
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
          Result::Success.new(data: { txid: result.data.strip })
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
