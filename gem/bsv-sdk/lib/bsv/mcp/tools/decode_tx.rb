# frozen_string_literal: true

module BSV
  module MCP
    module Tools
      # Decodes a raw BSV transaction from hex and returns a structured
      # human-readable representation.
      #
      # Supports standard raw hex only (not BEEF format). The txid is
      # returned in display byte order (reversed from the wire hash),
      # matching block explorer conventions.
      class DecodeTx < ::MCP::Tool
        tool_name 'decode_tx'

        description <<~DESC.strip
          Decode a raw BSV transaction hex string into a structured JSON object.

          Accepts standard raw transaction hex (not BEEF format). Returns:
          - txid: transaction ID in display byte order (as seen in block explorers)
          - version: transaction version number (typically 1)
          - lock_time: transaction locktime (0 means no locktime)
          - inputs: array of inputs, each with:
            - prev_txid: the txid of the output being spent
            - vout: output index in the previous transaction
            - script_hex: raw unlocking script as hex
            - script_asm: unlocking script in ASM notation
            - sequence: input sequence number
          - outputs: array of outputs, each with:
            - index: output index in this transaction
            - satoshis: value in satoshis
            - script_hex: raw locking script as hex
            - script_asm: locking script in ASM notation
            - script_type: detected script type (pubkeyhash, nulldata, pubkey, etc.)

          Note: input prev_txids are shown in display byte order. The raw wire
          format stores them reversed; this tool normalises them for readability.
        DESC

        input_schema(
          type: 'object',
          properties: {
            hex: {
              type: 'string',
              description: 'Raw transaction hex string (not BEEF format).'
            }
          },
          required: ['hex']
        )

        def self.call(hex:, **)
          tx = BSV::Transaction::Transaction.from_hex(hex)
          result = transaction_to_h(tx)

          ::MCP::Tool::Response.new(
            [::MCP::Content::Text.new(result.to_json)],
            structured_content: result
          )
        rescue ArgumentError => e
          error_result = { error: e.message }
          ::MCP::Tool::Response.new(
            [::MCP::Content::Text.new(error_result.to_json)],
            error: true
          )
        end

        # @api private
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
