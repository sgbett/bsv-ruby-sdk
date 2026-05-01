# frozen_string_literal: true

module BSV
  module MCP
    module Tools
      # Fetches a transaction from the BSV network by its txid using the
      # WhatsOnChain API, returning both the raw hex and decoded structure.
      class FetchTx < ::MCP::Tool
        tool_name 'fetch_tx'

        description <<~DESC.strip
          Fetch a transaction from the BSV network by its transaction ID.

          Queries the WhatsOnChain API and returns the raw transaction hex
          plus a decoded representation of its structure. Requires network access.

          Parameters:
          - txid: 64-character hex transaction ID (as shown in block explorers)
          - network: 'mainnet' or 'testnet' — overrides the server default

          Returns:
          - txid: the transaction ID (confirmed by parsing)
          - hex: raw transaction hex
          - version: transaction version number
          - lock_time: transaction locktime (0 = no locktime)
          - inputs: array of inputs (prev_txid, vout, script_hex, script_asm, sequence)
          - outputs: array of outputs (index, satoshis, script_hex, script_asm, script_type)

          Note: WhatsOnChain returns raw transaction hex (not BEEF or EF format).
          The txid in the response is derived by double-SHA-256 of the parsed tx,
          and is shown in display byte order (matching block explorers).
        DESC

        input_schema(
          type: 'object',
          properties: {
            txid: {
              type: 'string',
              description: '64-character hex transaction ID.'
            },
            network: {
              type: 'string',
              enum: %w[mainnet testnet],
              description: 'Network to query. Overrides the server default.'
            }
          },
          required: ['txid']
        )

        def self.call(txid:, network: nil, server_context: nil)
          net_sym = Helpers.resolve_network_sym(network, server_context)
          provider = BSV::Network::Providers::WhatsOnChain.default(network: net_sym)
          fetch_result = provider.call(:get_tx, txid)

          unless fetch_result.success?
            code = fetch_result.metadata[:status_code]
            msg = fetch_result.message
            msg = "#{msg} (HTTP #{code})" if code
            return Helpers.error_response(msg)
          end

          tx = BSV::Transaction::Transaction.from_hex(fetch_result.data)

          result = {
            hex: tx.to_hex,
            network: net_sym.to_s
          }.merge(Helpers.transaction_to_h(tx))

          ::MCP::Tool::Response.new(
            [::MCP::Content::Text.new(result.to_json)],
            structured_content: result
          )
        rescue ArgumentError => e
          Helpers.error_response(e.message)
        end
      end
    end
  end
end
