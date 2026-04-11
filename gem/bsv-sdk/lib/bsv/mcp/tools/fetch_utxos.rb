# frozen_string_literal: true

module BSV
  module MCP
    module Tools
      # Fetches unspent transaction outputs (UTXOs) for a BSV address using
      # the WhatsOnChain API.
      #
      # The http_client dependency is injectable for testing — pass a
      # compatible mock object to +new_woc+.
      class FetchUtxos < ::MCP::Tool
        tool_name 'fetch_utxos'

        description <<~DESC.strip
          Fetch unspent transaction outputs (UTXOs) for a BSV address.

          Queries the WhatsOnChain API and returns the list of UTXOs available
          to spend from the given address. Requires network access.

          Parameters:
          - address: a BSV P2PKH address (mainnet starts with '1'; testnet
            starts with 'm' or 'n')
          - network: 'mainnet' or 'testnet' — overrides the server default

          Returns an array of UTXO objects, each with:
          - tx_hash: transaction ID of the UTXO
          - tx_pos: output index within that transaction
          - satoshis: value in satoshis
          - height: block height (0 = unconfirmed)

          Note: addresses are network-specific. A mainnet address on testnet
          (or vice versa) will return no results or an error.
        DESC

        input_schema(
          type: 'object',
          properties: {
            address: {
              type: 'string',
              description: 'BSV P2PKH address to look up.'
            },
            network: {
              type: 'string',
              enum: %w[mainnet testnet],
              description: 'Network to query. Overrides the server default.'
            }
          },
          required: ['address']
        )

        def self.call(address:, network: nil, server_context: nil)
          net_sym = Helpers.resolve_network_sym(network, server_context)
          woc = BSV::Network::WhatsOnChain.new(network: net_sym)
          utxos = woc.fetch_utxos(address)

          result = {
            address: address,
            network: net_sym.to_s,
            utxos: utxos.map { |u| Helpers.utxo_to_h(u) }
          }

          ::MCP::Tool::Response.new(
            [::MCP::Content::Text.new(result.to_json)],
            structured_content: result
          )
        rescue BSV::Network::ChainProviderError => e
          Helpers.error_response("#{e.message} (HTTP #{e.status_code})")
        end
      end
    end
  end
end
