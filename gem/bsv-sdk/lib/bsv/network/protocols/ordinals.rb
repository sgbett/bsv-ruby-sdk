# frozen_string_literal: true

require 'json'

module BSV
  module Network
    module Protocols
      # Ordinals implements the GorillaPool Ordinals API as a Protocol subclass.
      #
      # Provides raw transaction lookup, Merkle path (proof) retrieval, UTXO
      # queries, balance lookups, spend status, and chain tip via the GorillaPool
      # Ordinals REST API.
      #
      # == get_tx vs get_tx_details
      #
      # +get_tx+ returns the raw transaction as a hex string (escape hatch
      # converts binary response body to hex). +get_tx_details+ returns the full
      # parsed transaction metadata as a JSON object.
      #
      # == get_balance
      #
      # The API returns the balance as a quoted integer string (e.g. +"1000000"+),
      # not a bare JSON number. The lambda handler parses this to an Integer.
      #
      # == get_spend
      #
      # The API returns an empty quoted string +""+  for unspent outputs and a
      # quoted txid string for spent outputs. The escape hatch normalises these
      # to +{ spent: false }+ or +{ spent: true, spending_txid: "..." }+.
      # The outpoint must be passed as +"txid_vout"+ (underscore-separated).
      #
      # == Usage
      #
      #   ord = BSV::Network::Protocols::Ordinals.new(base_url: 'https://ordinals.gorillapool.io')
      #   result = ord.call(:get_tx, 'abc123...')
      #   result.data  # => "01000000..."  (hex string)
      #
      #   result = ord.call(:get_merkle_path, 'abc123...')
      #   result.data  # => binary TSC proof bytes
      #
      #   result = ord.call(:get_spend, 'txid_0')
      #   result.data  # => { spent: false } or { spent: true, spending_txid: "..." }
      #
      # @see https://ordinals.gorillapool.io/api/docs/ Ordinals API documentation
      class Ordinals < Protocol
        # Transaction — raw binary body; escape hatch converts to hex
        endpoint :get_tx,         :get, '/api/tx/{txid}/raw'

        # Transaction — full metadata as JSON
        endpoint :get_tx_details, :get, '/api/tx/{txid}', response: :json

        # Transaction — confirmation status
        endpoint :get_tx_status,  :get, '/api/tx/{txid}/status', response: :json

        # Merkle path — binary TSC proof body; no JSON parsing
        endpoint :get_merkle_path, :get, '/api/tx/{txid}/proof'

        # UTXOs for an address — JSON array
        endpoint :get_utxos, :get, '/api/txos/address/{address}/unspent', response: :json_array

        # Balance for an address — quoted integer string; lambda parses to Integer
        endpoint :get_balance, :get, '/api/txos/address/{address}/balance',
                 response: ->(body) { JSON.parse(body).to_i }

        # Spend status for an outpoint (format: "txid_vout") — escape hatch normalises
        endpoint :get_spend, :get, '/api/spends/{outpoint}'

        # Chain tip — latest block metadata as JSON
        endpoint :get_chain_tip, :get, '/api/blocks/tip', response: :json

        # @param base_url    [String] base URL for the Ordinals API
        # @param api_key     [String, nil] legacy Bearer API key shorthand — use +auth:+ for new code
        # @param auth        [Hash, Symbol, nil] auth config; takes precedence over +api_key:+
        # @param http_client [Object, nil] injectable HTTP client for testing
        def initialize(base_url:, api_key: nil, auth: nil, http_client: nil)
          super
        end

        private

        # Fetches the raw transaction and converts the binary response body to hex.
        #
        # The Ordinals API serves +/api/tx/{txid}/raw+ as binary data, not hex text.
        # This escape hatch unpacks the binary body to a lowercase hex string,
        # matching the convention used by other protocol +get_tx+ implementations.
        #
        # Accepts +txid+ as a positional argument or as a +txid:+ keyword.
        #
        # @param pos_txid [String, nil] transaction ID (positional form)
        # @param txid     [String, nil] transaction ID (keyword form)
        # @return [ProtocolResponse]
        def call_get_tx(pos_txid = nil, txid: nil)
          resolved = pos_txid || txid
          raise ArgumentError, 'txid is required' if resolved.nil? || resolved.empty?

          result = default_call(:get_tx, resolved)
          return result unless result.success?
          return result.with(ok: false, error_message: 'empty response body') if result.data.nil? || result.data.empty?

          result.with(data: result.data.unpack1('H*'))
        end

        # Normalises the spend status response from the Ordinals API.
        #
        # The API returns a quoted empty string +""+  when the output is unspent,
        # and a quoted txid string +"abc123..."+ when it is spent. This escape
        # hatch parses the JSON string body and returns a structured hash.
        #
        # The +outpoint+ argument must use underscore-separated format: +"txid_vout"+.
        # Accepts +outpoint+ as a positional argument or as an +outpoint:+ keyword.
        #
        # @param pos_outpoint [String, nil] outpoint in +"txid_vout"+ format (positional form)
        # @param outpoint     [String, nil] outpoint in +"txid_vout"+ format (keyword form)
        # @return [ProtocolResponse]
        def call_get_spend(pos_outpoint = nil, outpoint: nil)
          resolved = pos_outpoint || outpoint
          raise ArgumentError, 'outpoint is required' if resolved.nil? || resolved.empty?

          result = default_call(:get_spend, resolved)
          return result unless result.success?

          spending_txid = JSON.parse(result.data).to_s.strip
          if spending_txid.empty?
            result.with(data: { spent: false })
          else
            result.with(data: { spent: true, spending_txid: spending_txid })
          end
        rescue JSON::ParserError => e
          result.with(ok: false, error_message: "spend response parse error: #{e.message}")
        end
      end
    end
  end
end
