# frozen_string_literal: true

module BSV
  module Script
    class Builder
      def initialize
        @chunks = []
      end

      # Push an opcode by symbol (:OP_DUP) or integer (0x76)
      def push_op(opcode)
        code = opcode.is_a?(Symbol) ? Opcodes.const_get(opcode) : opcode
        @chunks << Chunk.new(opcode: code)
        self
      end

      # Push raw binary data (handles all PUSHDATA encodings)
      def push_data(data)
        bytes = data.b
        @chunks << Chunk.new(opcode: push_opcode_for(bytes.bytesize), data: bytes)
        self
      end

      # Push hex-encoded data
      def push_hex(hex)
        push_data([hex].pack('H*'))
      end

      def build
        Script.from_chunks(@chunks)
      end

      private

      def push_opcode_for(len)
        if len <= 0x4b
          len
        elsif len <= 0xff
          Opcodes::OP_PUSHDATA1
        elsif len <= 0xffff
          Opcodes::OP_PUSHDATA2
        else
          Opcodes::OP_PUSHDATA4
        end
      end
    end
  end
end
