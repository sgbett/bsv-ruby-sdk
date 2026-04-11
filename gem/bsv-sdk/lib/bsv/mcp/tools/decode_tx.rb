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
          result = Helpers.transaction_to_h(tx)

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
