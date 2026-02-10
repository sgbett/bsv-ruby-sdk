# frozen_string_literal: true

module BSV
  module Transaction
    class TransactionInput
      attr_reader :prev_tx_id, :prev_tx_out_index, :sequence
      attr_accessor :unlocking_script, :source_satoshis, :source_locking_script,
                    :source_transaction, :unlocking_script_template

      def initialize(prev_tx_id:, prev_tx_out_index:, unlocking_script: nil, sequence: 0xFFFFFFFF)
        @prev_tx_id = prev_tx_id.b
        @prev_tx_out_index = prev_tx_out_index
        @unlocking_script = unlocking_script
        @sequence = sequence
      end

      def to_binary
        script_bytes = @unlocking_script ? @unlocking_script.to_binary : ''.b
        @prev_tx_id +
          [@prev_tx_out_index].pack('V') +
          VarInt.encode(script_bytes.bytesize) +
          script_bytes +
          [@sequence].pack('V')
      end

      def self.from_binary(data, offset = 0)
        prev_tx_id = data.byteslice(offset, 32)
        prev_tx_out_index = data.byteslice(offset + 32, 4).unpack1('V')
        offset += 36

        script_len, vi_size = VarInt.decode(data, offset)
        offset += vi_size

        unlocking_script = (BSV::Script::Script.from_binary(data.byteslice(offset, script_len)) if script_len.positive?)
        offset += script_len

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

      def self.txid_from_hex(hex)
        [hex].pack('H*').reverse
      end

      def outpoint_binary
        @prev_tx_id + [@prev_tx_out_index].pack('V')
      end

      def txid_hex
        @prev_tx_id.reverse.unpack1('H*')
      end
    end
  end
end
