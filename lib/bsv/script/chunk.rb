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
      # Opcodes with no defined name are rendered as +OP_UNKNOWN<n>+ (e.g.
      # +OP_UNKNOWN186+) so that the output is unambiguous and round-trippable
      # via +from_asm+.
      #
      # The OP_RETURN opcode is special: it carries the raw tail bytes as its
      # data payload (absorbed during parsing). To preserve round-trip fidelity
      # with +from_asm+, the tail is re-parsed into individual push items and
      # each is rendered as a hex token after +OP_RETURN+.
      #
      # @return [String] ASM representation
      def to_asm
        if @opcode == Opcodes::OP_RETURN && @data
          return 'OP_RETURN' if @data.empty?

          # Re-parse the tail bytes into individual chunks (without OP_RETURN
          # termination) so each push renders as a separate hex token.
          tail_script = BSV::Script::Script.new(@data)
          tail_chunks = tail_script.send(:parse_chunks, terminate_on_op_return: false)
          parts = ['OP_RETURN'] + tail_chunks.map do |ch|
            ch.data? ? ch.data.unpack1('H*') : (Opcodes.name_for(ch.opcode) || "OP_UNKNOWN#{ch.opcode}")
          end
          parts.join(' ')
        elsif @data
          @data.unpack1('H*')
        else
          Opcodes.name_for(@opcode) || "OP_UNKNOWN#{@opcode}"
        end
      end

      # @param other [Object] the object to compare
      # @return [Boolean] +true+ if both chunks have equal opcode and data
      def ==(other)
        other.is_a?(Chunk) && @opcode == other.opcode && @data == other.data
      end
    end
  end
end
