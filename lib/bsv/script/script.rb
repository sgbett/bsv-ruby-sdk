# frozen_string_literal: true

module BSV
  module Script
    class Script
      attr_reader :bytes

      def initialize(bytes = ''.b)
        @bytes = bytes.b
        @chunks = nil
      end

      def self.from_binary(binary)
        new(binary)
      end

      def self.from_hex(hex)
        new([hex].pack('H*'))
      end

      def self.from_asm(asm_string)
        buf = ''.b
        asm_string.split.each do |token|
          opcode = resolve_opcode(token)
          if opcode
            buf << [opcode].pack('C')
          else
            # Data push — token is hex
            data = [token].pack('H*')
            buf << encode_push_data(data)
          end
        end
        new(buf)
      end

      def self.from_chunks(chunks)
        buf = chunks.map(&:to_binary).join
        script = new(buf)
        script.instance_variable_set(:@chunks, chunks.dup)
        script
      end

      def self.builder
        Builder.new
      end

      # --- Templates ---

      def self.op_return(*data_items)
        buf = [Opcodes::OP_FALSE, Opcodes::OP_RETURN].pack('CC')
        data_items.each { |d| buf << encode_push_data(d.b) }
        new(buf)
      end

      def self.p2pkh_lock(pubkey_hash)
        raise ArgumentError, 'pubkey_hash must be 20 bytes' unless pubkey_hash.bytesize == 20

        buf = [
          Opcodes::OP_DUP,
          Opcodes::OP_HASH160
        ].pack('CC')
        buf << encode_push_data(pubkey_hash)
        buf << [Opcodes::OP_EQUALVERIFY, Opcodes::OP_CHECKSIG].pack('CC')
        new(buf)
      end

      def self.p2pkh_unlock(signature_der, pubkey_bytes)
        buf = encode_push_data(signature_der)
        buf << encode_push_data(pubkey_bytes)
        new(buf)
      end

      # --- Serialisation ---

      def to_binary
        @bytes.dup
      end

      def to_hex
        @bytes.unpack1('H*')
      end

      def to_asm
        chunks.map(&:to_asm).join(' ')
      end

      def length
        @bytes.bytesize
      end

      # --- Chunk parsing (lazy) ---

      def chunks
        @chunks ||= parse_chunks
      end

      def ==(other)
        other.is_a?(self.class) && @bytes == other.bytes
      end

      class << self
        private

        def encode_push_data(data)
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

        def resolve_opcode(token)
          return nil unless token.start_with?('OP_')

          Opcodes.const_get(token.to_sym)
        rescue NameError
          nil
        end
      end

      private

      def parse_chunks
        result = []
        pos = 0
        raw = @bytes

        while pos < raw.bytesize
          opcode = raw.getbyte(pos)
          pos += 1

          if opcode.positive? && opcode <= 0x4b
            data = raw.byteslice(pos, opcode)
            pos += opcode
            result << Chunk.new(opcode: opcode, data: data)
          elsif opcode == Opcodes::OP_PUSHDATA1
            len = raw.getbyte(pos)
            pos += 1
            data = raw.byteslice(pos, len)
            pos += len
            result << Chunk.new(opcode: opcode, data: data)
          elsif opcode == Opcodes::OP_PUSHDATA2
            len = raw.byteslice(pos, 2).unpack1('v')
            pos += 2
            data = raw.byteslice(pos, len)
            pos += len
            result << Chunk.new(opcode: opcode, data: data)
          elsif opcode == Opcodes::OP_PUSHDATA4
            len = raw.byteslice(pos, 4).unpack1('V')
            pos += 4
            data = raw.byteslice(pos, len)
            pos += len
            result << Chunk.new(opcode: opcode, data: data)
          else
            result << Chunk.new(opcode: opcode)
          end
        end

        result
      end
    end
  end
end
