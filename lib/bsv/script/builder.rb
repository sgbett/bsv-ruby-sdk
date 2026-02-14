# frozen_string_literal: true

module BSV
  module Script
    # Fluent builder for constructing scripts incrementally.
    #
    # Provides a chainable API for building scripts from opcodes and data
    # pushes, as an alternative to the template constructors on {Script}.
    #
    # @example Build a custom script
    #   script = BSV::Script::Script.builder
    #     .push_op(:OP_DUP)
    #     .push_op(:OP_HASH160)
    #     .push_data(pubkey_hash)
    #     .push_op(:OP_EQUALVERIFY)
    #     .push_op(:OP_CHECKSIG)
    #     .build
    class Builder
      def initialize
        @chunks = []
      end

      # Push an opcode onto the script.
      #
      # @param opcode [Symbol, Integer] opcode name (e.g. +:OP_DUP+) or byte value
      # @return [self] for chaining
      def push_op(opcode)
        code = opcode.is_a?(Symbol) ? Opcodes.const_get(opcode) : opcode
        @chunks << Chunk.new(opcode: code)
        self
      end

      # Push raw binary data (automatically selects PUSHDATA encoding).
      #
      # @param data [String] binary data to push
      # @return [self] for chaining
      def push_data(data)
        bytes = data.b
        @chunks << Chunk.new(opcode: push_opcode_for(bytes.bytesize), data: bytes)
        self
      end

      # Push hex-encoded data.
      #
      # @param hex [String] hex-encoded data to push
      # @return [self] for chaining
      def push_hex(hex)
        push_data([hex].pack('H*'))
      end

      # Finalise and return the constructed {Script}.
      #
      # @return [Script] the built script
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
