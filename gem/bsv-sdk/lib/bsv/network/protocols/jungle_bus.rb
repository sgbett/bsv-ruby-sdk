# frozen_string_literal: true

module BSV
  module Network
    module Protocols
      # JungleBus implements the GorillaPool JungleBus REST API as a Protocol
      # subclass.
      #
      # JungleBus is a blockchain indexer that indexes all BSV transactions and
      # provides parsed transaction data, address lookups, and block headers.
      # The +get_tx+ endpoint returns both the full transaction (base64-encoded)
      # and a TSC merkle proof in a single call.
      #
      # == Usage
      #
      #   jb = BSV::Network::Protocols::JungleBus.new(
      #     base_url: 'https://junglebus.gorillapool.io'
      #   )
      #   result = jb.call(:get_tx, 'abc123...')
      #   result.data['transaction']  # => base64-encoded raw tx
      #   result.data['merkle_proof'] # => base64-encoded TSC proof (or nil)
      class JungleBus < Protocol
        # Transaction — full tx with parsed metadata and merkle proof
        endpoint :get_tx, :get, '/v1/transaction/get/{txid}', response: :json

        # Address — transaction metadata for an address
        endpoint :get_address_meta, :get, '/v1/address/get/{address}', response: :json_array

        # Address — full transaction documents for an address.
        # Note: this endpoint currently returns empty bodies for all addresses
        # via the REST API. It may require a subscription to populate.
        endpoint :get_address_txs, :get, '/v1/address/transactions/{address}', response: :json_array

        # Block header by height or hash
        endpoint :get_block_header, :get, '/v1/block_header/get/{height}', response: :json

        # Block headers from a given height (supports ?limit=N, max 10000)
        endpoint :get_block_headers, :get, '/v1/block_header/list/{height}', response: :json_array

        # @param base_url    [String] base URL for the JungleBus API
        # @param api_key     [String, nil] legacy API key shorthand — use +auth:+ for new code
        # @param auth        [Hash, Symbol, nil] auth config; takes precedence over +api_key:+
        # @param http_client [Object, nil] injectable HTTP client for testing
        def initialize(base_url:, api_key: nil, auth: nil, http_client: nil)
          super
        end
      end
    end
  end
end
