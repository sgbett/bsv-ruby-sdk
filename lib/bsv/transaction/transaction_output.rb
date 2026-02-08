# frozen_string_literal: true

module BSV
  module Transaction
    class TransactionOutput
      attr_reader :satoshis, :locking_script

      def initialize(satoshis:, locking_script:)
        @satoshis = satoshis
        @locking_script = locking_script
      end

      def to_binary
        script_bytes = @locking_script.to_binary
        [satoshis].pack('Q<') + VarInt.encode(script_bytes.bytesize) + script_bytes
      end

      def self.from_binary(data, offset = 0)
        satoshis = data.byteslice(offset, 8).unpack1('Q<')
        offset += 8

        script_len, vi_size = VarInt.decode(data, offset)
        offset += vi_size

        script_bytes = data.byteslice(offset, script_len)
        locking_script = BSV::Script::Script.from_binary(script_bytes)

        [new(satoshis: satoshis, locking_script: locking_script), 8 + vi_size + script_len]
      end
    end
  end
end
