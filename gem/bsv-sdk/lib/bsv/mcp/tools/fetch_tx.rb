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
          net_sym = resolve_network_sym(network, server_context)
          woc = BSV::Network::WhatsOnChain.new(network: net_sym)
          tx = woc.fetch_transaction(txid)

          result = {
            hex: tx.to_hex,
            network: net_sym.to_s
          }.merge(transaction_to_h(tx))

          ::MCP::Tool::Response.new(
            [::MCP::Content::Text.new(result.to_json)],
            structured_content: result
          )
        rescue BSV::Network::ChainProviderError => e
          error_result = { error: e.message, status_code: e.status_code }
          ::MCP::Tool::Response.new(
            [::MCP::Content::Text.new(error_result.to_json)],
            error: true
          )
        rescue ArgumentError => e
          error_result = { error: e.message }
          ::MCP::Tool::Response.new(
            [::MCP::Content::Text.new(error_result.to_json)],
            error: true
          )
        end

        # @api private
        def self.resolve_network_sym(network_arg, server_context)
          net = network_arg
          net = server_context[:bsv_network] if net.nil? && server_context.is_a?(Hash) && server_context[:bsv_network]
          net == 'testnet' ? :testnet : :mainnet
        end
        private_class_method :resolve_network_sym

        def self.transaction_to_h(tx)
          {
            txid: tx.txid_hex,
            version: tx.version,
            lock_time: tx.lock_time,
            inputs: tx.inputs.each_with_index.map { |inp, i| input_to_h(inp, i) },
            outputs: tx.outputs.each_with_index.map { |out, i| output_to_h(out, i) }
          }
        end
        private_class_method :transaction_to_h

        def self.input_to_h(input, _index)
          unlock_script = input.unlocking_script
          {
            prev_txid: input.prev_tx_id.reverse.unpack1('H*'),
            vout: input.prev_tx_out_index,
            script_hex: unlock_script ? unlock_script.to_hex : '',
            script_asm: unlock_script ? unlock_script.to_asm : '',
            sequence: input.sequence
          }
        end
        private_class_method :input_to_h

        def self.output_to_h(output, index)
          script = output.locking_script
          {
            index: index,
            satoshis: output.satoshis,
            script_hex: script ? script.to_hex : '',
            script_asm: script ? script.to_asm : '',
            script_type: script ? script.type : 'empty'
          }
        end
        private_class_method :output_to_h
      end
    end
  end
end
