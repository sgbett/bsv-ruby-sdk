# frozen_string_literal: true

module BSV
  module Script
    class Chunk
      attr_reader :opcode, :data

      def initialize(opcode:, data: nil)
        @opcode = opcode
        @data = data&.b
      end

      def data?
        !@data.nil?
      end

      def to_binary
        if @data
          push_data_binary(@data)
        else
          [@opcode].pack('C')
        end
      end

      def to_asm
        if @data
          @data.unpack1('H*')
        else
          Opcodes.name_for(@opcode) || @opcode.to_s
        end
      end

      def ==(other)
        other.is_a?(Chunk) && @opcode == other.opcode && @data == other.data
      end

      private

      def push_data_binary(data)
        len = data.bytesize

        if len <= 0x4b
          [len].pack('C') + data
        elsif len <= 0xff
          [Opcodes::OP_PUSHDATA1, len].pack('CC') + data
        elsif len <= 0xffff
          [Opcodes::OP_PUSHDATA2, len].pack('Cv') + data
        else
          [Opcodes::OP_PUSHDATA4, len].pack('CV') + data
        end
      end
    end
  end
end
