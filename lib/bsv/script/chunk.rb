# frozen_string_literal: true

module BSV
  module Script
    # A single element of a parsed script — either an opcode or a data push.
    #
    # Scripts are composed of a sequence of chunks. Each chunk is either
    # a bare opcode (e.g. +OP_DUP+) or a data push (opcode + data payload).
    class Chunk
      # @return [Integer] the opcode byte
      attr_reader :opcode

      # @return [String, nil] the pushed data bytes, or +nil+ for bare opcodes
      attr_reader :data

      # @param opcode [Integer] the opcode byte value
      # @param data [String, nil] data payload for push operations
      def initialize(opcode:, data: nil)
        @opcode = opcode
        @data = data&.b
      end

      # Whether this chunk carries a data payload.
      #
      # @return [Boolean] +true+ if this is a data push chunk
      def data?
        !@data.nil?
      end

      # Serialise this chunk back to raw script bytes.
      #
      # Preserves the original push encoding (including non-minimal pushes)
      # so that round-tripping through parse/serialise does not alter the
      # script bytes. This is critical for sighash computation.
      #
      # @return [String] binary script bytes for this chunk
      def to_binary
        return [@opcode].pack('C') unless @data

        case @opcode
        when Opcodes::OP_PUSHDATA1
          [Opcodes::OP_PUSHDATA1, @data.bytesize].pack('CC') + @data
        when Opcodes::OP_PUSHDATA2
          [Opcodes::OP_PUSHDATA2].pack('C') + [@data.bytesize].pack('v') + @data
        when Opcodes::OP_PUSHDATA4
          [Opcodes::OP_PUSHDATA4].pack('C') + [@data.bytesize].pack('V') + @data
        else
          # Direct push: opcode IS the length (0x01..0x4b)
          [@opcode].pack('C') + @data
        end
      end

      # Render this chunk as human-readable ASM.
      #
      # Data pushes are shown as hex strings; opcodes are shown by name.
      #
      # @return [String] ASM representation
      def to_asm
        if @data
          @data.unpack1('H*')
        else
          Opcodes.name_for(@opcode) || @opcode.to_s
        end
      end

      # @param other [Object] the object to compare
      # @return [Boolean] +true+ if both chunks have equal opcode and data
      def ==(other)
        other.is_a?(Chunk) && @opcode == other.opcode && @data == other.data
      end

      private
    end
  end
end
