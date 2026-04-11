# frozen_string_literal: true

module BSV
  module Transaction
    # A transaction input referencing a previous output to spend.
    #
    # Inputs identify the output being spent by its transaction ID and
    # output index (the "outpoint"), and provide an unlocking script to
    # satisfy the locking script conditions.
    class TransactionInput
      # @return [String] 32-byte transaction ID of the output being spent (internal byte order)
      attr_reader :prev_tx_id

      # @return [Integer] index of the output within the previous transaction
      attr_reader :prev_tx_out_index

      # @return [Integer] sequence number (default: 0xFFFFFFFF)
      attr_reader :sequence

      # @return [Script::Script, nil] the unlocking script (set after signing)
      attr_accessor :unlocking_script

      # @return [Integer, nil] satoshi value of the source output (needed for sighash)
      attr_accessor :source_satoshis

      # @return [Script::Script, nil] locking script of the source output (needed for sighash)
      attr_accessor :source_locking_script

      # @return [Transaction, nil] the full source transaction (for BEEF wiring)
      attr_accessor :source_transaction

      # @return [UnlockingScriptTemplate, nil] template for deferred signing
      attr_accessor :unlocking_script_template

      # @param prev_tx_id [String] 32-byte transaction ID (internal byte order)
      # @param prev_tx_out_index [Integer] output index in the previous transaction
      # @param unlocking_script [Script::Script, nil] unlocking script (nil if unsigned)
      # @param sequence [Integer] sequence number
      def initialize(prev_tx_id:, prev_tx_out_index:, unlocking_script: nil, sequence: 0xFFFFFFFF)
        @prev_tx_id = prev_tx_id.b
        @prev_tx_out_index = prev_tx_out_index
        @unlocking_script = unlocking_script
        @sequence = sequence
      end

      # Serialise the input to its binary wire format.
      #
      # @return [String] binary input (outpoint + varint + script + sequence)
      def to_binary
        script_bytes = @unlocking_script ? @unlocking_script.to_binary : ''.b
        @prev_tx_id +
          [@prev_tx_out_index].pack('V') +
          VarInt.encode(script_bytes.bytesize) +
          script_bytes +
          [@sequence].pack('V')
      end

      # Deserialise a transaction input from binary data.
      #
      # @param data [String] binary data
      # @param offset [Integer] byte offset to start reading from
      # @return [Array(TransactionInput, Integer)] the input and bytes consumed
      def self.from_binary(data, offset = 0)
        if data.bytesize < offset + 36
          raise ArgumentError,
                "truncated input: need 36 bytes for outpoint at offset #{offset}, got #{data.bytesize - offset}"
        end

        prev_tx_id = data.byteslice(offset, 32)
        prev_tx_out_index = data.byteslice(offset + 32, 4).unpack1('V')
        offset += 36

        script_len, vi_size = VarInt.decode(data, offset)
        offset += vi_size

        if data.bytesize < offset + script_len
          raise ArgumentError,
                "truncated input: need #{script_len} bytes for script at offset #{offset}, got #{data.bytesize - offset}"
        end

        unlocking_script = (BSV::Script::Script.from_binary(data.byteslice(offset, script_len)) if script_len.positive?)
        offset += script_len

        if data.bytesize < offset + 4
          raise ArgumentError,
                "truncated input: need 4 bytes for sequence at offset #{offset}, got #{data.bytesize - offset}"
        end

        sequence = data.byteslice(offset, 4).unpack1('V')

        total = 36 + vi_size + script_len + 4
        input = new(
          prev_tx_id: prev_tx_id,
          prev_tx_out_index: prev_tx_out_index,
          unlocking_script: unlocking_script,
          sequence: sequence
        )
        [input, total]
      end

      # Convert a hex transaction ID to internal byte order (reversed).
      #
      # @param hex [String] hex-encoded transaction ID (display order)
      # @return [String] 32-byte transaction ID in internal byte order
      def self.txid_from_hex(hex)
        [hex].pack('H*').reverse
      end

      # Serialise the outpoint (prev_tx_id + output index) as binary.
      #
      # @return [String] 36-byte outpoint
      def outpoint_binary
        @prev_tx_id + [@prev_tx_out_index].pack('V')
      end

      # The previous transaction ID in hex (display order).
      #
      # @return [String] hex-encoded transaction ID
      def txid_hex
        @prev_tx_id.reverse.unpack1('H*')
      end
    end
  end
end
