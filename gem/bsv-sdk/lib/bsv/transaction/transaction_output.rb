# frozen_string_literal: true

module BSV
  module Transaction
    # A transaction output specifying an amount and spending conditions.
    #
    # Each output locks a number of satoshis behind a locking script.
    # Outputs are consumed by transaction inputs that provide matching
    # unlocking scripts.
    class TransactionOutput
      # @return [Integer] the output value in satoshis
      attr_accessor :satoshis

      # @return [Script::Script] the locking script (spending conditions)
      attr_accessor :locking_script

      # @return [Boolean] whether this output receives change
      attr_accessor :change

      # @param satoshis [Integer] output value in satoshis
      # @param locking_script [Script::Script] the locking script
      # @param change [Boolean] whether this is a change output (default: false)
      def initialize(satoshis:, locking_script:, change: false)
        @satoshis = satoshis
        @locking_script = locking_script
        @change = change
        @owning_tx = nil
      end

      # Called by +#dup+ and +#clone+. Clears the owning-Tx backref so that the
      # cloned output does not belong to any transaction until it is explicitly
      # added via +Tx#add_output+.
      def initialize_copy(other)
        super
        @owning_tx = nil
      end

      # Serialise the output to its binary wire format.
      #
      # @return [String] binary output (8-byte LE satoshis + varint + script)
      def to_binary
        script_bytes = @locking_script.to_binary
        [satoshis].pack('Q<') + VarInt.encode(script_bytes.bytesize) + script_bytes
      end

      # Deserialise a transaction output from binary data.
      #
      # @param data [String] binary data
      # @param offset [Integer] byte offset to start reading from
      # @return [Array(TransactionOutput, Integer)] the output and bytes consumed
      def self.from_binary(data, offset = 0)
        if data.bytesize < offset + 8
          raise ArgumentError,
                "truncated output: need 8 bytes for satoshis at offset #{offset}, got #{data.bytesize - offset}"
        end

        satoshis = data.byteslice(offset, 8).unpack1('Q<')
        offset += 8

        script_len, vi_size = VarInt.decode(data, offset)
        offset += vi_size

        if data.bytesize < offset + script_len
          raise ArgumentError,
                "truncated output: need #{script_len} bytes for script at offset #{offset}, got #{data.bytesize - offset}"
        end

        script_bytes = data.byteslice(offset, script_len)
        locking_script = BSV::Script::Script.from_binary(script_bytes)

        [new(satoshis: satoshis, locking_script: locking_script), 8 + vi_size + script_len]
      end
    end
  end
end
