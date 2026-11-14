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

          Note: addresses are network-specific. An address for the other
          network, or one that is not a P2PKH address, is rejected without
          any request being made.
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
          address = AddressInput.resolve(address, net_sym)
          provider = BSV::Network::Providers::WhatsOnChain.default(network: net_sym)
          utxo_result = provider.call(:get_utxos_all, address)

          unless utxo_result.http_success?
            code = utxo_result.code
            msg = utxo_result.message
            msg = "#{msg} (HTTP #{code})" if code
            return Helpers.error_response(msg)
          end

          utxos = utxo_result.data.map do |entry|
            BSV::Network::UTXO.new(
              tx_hash: entry['tx_hash'], tx_pos: entry['tx_pos'],
              value: entry['value'], height: entry['height']
            )
          end

          result = {
            address: address,
            network: net_sym.to_s,
            utxos: utxos.map { |u| Helpers.utxo_to_h(u) }
          }

          Helpers.json_response(result)
        rescue ArgumentError => e
          Helpers.error_response(e.message)
        end
      end
    end
  end
end
