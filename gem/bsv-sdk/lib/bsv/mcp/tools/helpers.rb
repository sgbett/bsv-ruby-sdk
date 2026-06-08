# frozen_string_literal: true

module BSV
  module MCP
    module Tools
      # Shared helpers used across multiple MCP tools.
      module Helpers
        # Resolve a network string to the SDK symbol (:mainnet or :testnet).
        #
        # Checks the per-call +network_arg+ first, then falls back to the
        # server-level config in +server_context+, then defaults to :mainnet.
        #
        # @param network_arg [String, nil] per-call override ('mainnet'/'testnet')
        # @param server_context [Hash, nil] server context with :bsv_network key
        # @return [Symbol] :mainnet or :testnet
        def self.resolve_network_sym(network_arg, server_context)
          net = network_arg
          net = server_context[:bsv_network] if net.nil? && server_context.is_a?(Hash) && server_context[:bsv_network]
          net == 'testnet' ? :testnet : :mainnet
        end

        # Convert a Transaction to a hash suitable for JSON responses.
        #
        # @param tx [BSV::Transaction::Tx]
        # @return [Hash]
        def self.transaction_to_h(tx)
          {
            txid: tx.txid_hex, # MCP tool boundary: display-order hex for human consumption
            version: tx.version,
            lock_time: tx.lock_time,
            inputs: tx.inputs.each_with_index.map { |inp, i| input_to_h(inp, i) },
            outputs: tx.outputs.each_with_index.map { |out, i| output_to_h(out, i) }
          }
        end

        # Convert a TransactionInput to a hash.
        # @api private
        def self.input_to_h(input, _index)
          unlock_script = input.unlocking_script
          {
            prev_txid: input.dtxid_hex,
            vout: input.prev_tx_out_index,
            script_hex: unlock_script ? unlock_script.to_hex : '',
            script_asm: unlock_script ? unlock_script.to_asm : '',
            sequence: input.sequence
          }
        end

        # Convert a TransactionOutput to a hash.
        # @api private
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

        # Convert a UTXO to a hash.
        # @api private
        def self.utxo_to_h(utxo)
          {
            tx_hash: utxo.tx_hash,
            tx_pos: utxo.tx_pos,
            satoshis: utxo.satoshis,
            height: utxo.height
          }
        end

        # Build a standard MCP error response.
        #
        # @param message [String] error description
        # @return [MCP::Tool::Response]
        def self.error_response(message)
          payload = { error: message }
          ::MCP::Tool::Response.new(
            [::MCP::Content::Text.new(payload.to_json)],
            error: true
          )
        end
      end
    end
  end
end
