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

      def self.p2pk_lock(pubkey_bytes)
        raise ArgumentError, 'pubkey must be 33 or 65 bytes' unless [33, 65].include?(pubkey_bytes.bytesize)

        buf = encode_push_data(pubkey_bytes)
        buf << [Opcodes::OP_CHECKSIG].pack('C')
        new(buf)
      end

      def self.p2pk_unlock(signature_der)
        new(encode_push_data(signature_der))
      end

      def self.p2sh_lock(script_hash)
        raise ArgumentError, 'script_hash must be 20 bytes' unless script_hash.bytesize == 20

        buf = [Opcodes::OP_HASH160].pack('C')
        buf << encode_push_data(script_hash)
        buf << [Opcodes::OP_EQUAL].pack('C')
        new(buf)
      end

      def self.p2sh_unlock(redeem_script, *push_items)
        buf = ''.b
        push_items.each { |item| buf << encode_push_data(item.b) }
        buf << encode_push_data(redeem_script.to_binary)
        new(buf)
      end

      def self.p2ms_lock(required, pubkeys)
        n = pubkeys.length
        raise ArgumentError, 'm must be between 1 and n' unless required.between?(1, n)
        raise ArgumentError, 'n must be <= 16' unless n <= 16

        buf = [Opcodes::OP_1 + required - 1].pack('C')
        pubkeys.each { |pk| buf << encode_push_data(pk.b) }
        buf << [Opcodes::OP_1 + n - 1].pack('C')
        buf << [Opcodes::OP_CHECKMULTISIG].pack('C')
        new(buf)
      end

      def self.p2ms_unlock(*signatures)
        buf = [Opcodes::OP_0].pack('C')
        signatures.each { |sig| buf << encode_push_data(sig.b) }
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

      # --- Type predicates ---

      def p2pkh?
        b = @bytes
        b.bytesize == 25 &&
          b.getbyte(0) == Opcodes::OP_DUP &&
          b.getbyte(1) == Opcodes::OP_HASH160 &&
          b.getbyte(2) == 0x14 &&
          b.getbyte(23) == Opcodes::OP_EQUALVERIFY &&
          b.getbyte(24) == Opcodes::OP_CHECKSIG
      end

      def p2sh?
        b = @bytes
        b.bytesize == 23 &&
          b.getbyte(0) == Opcodes::OP_HASH160 &&
          b.getbyte(1) == 0x14 &&
          b.getbyte(22) == Opcodes::OP_EQUAL
      end

      def op_return?
        b = @bytes
        (b.bytesize.positive? && b.getbyte(0) == Opcodes::OP_RETURN) ||
          (b.bytesize > 1 && b.getbyte(0) == Opcodes::OP_FALSE && b.getbyte(1) == Opcodes::OP_RETURN)
      end

      def p2pk?
        c = chunks
        return false unless c.length == 2 && c[0].data? && c[1].opcode == Opcodes::OP_CHECKSIG

        pubkey = c[0].data
        version = pubkey.getbyte(0)
        ([0x02, 0x03].include?(version) && pubkey.bytesize == 33) ||
          ([0x04, 0x06, 0x07].include?(version) && pubkey.bytesize == 65)
      end

      def multisig?
        c = chunks
        return false if c.length < 3
        return false unless small_int_opcode?(c[0].opcode)
        return false unless small_int_opcode?(c[-2].opcode) && c[-1].opcode == Opcodes::OP_CHECKMULTISIG

        c[1..-3].all?(&:data?)
      end

      # --- Type classification ---

      def type
        if @bytes.empty? then 'empty'
        elsif p2pkh? then 'pubkeyhash'
        elsif p2pk? then 'pubkey'
        elsif p2sh? then 'scripthash'
        elsif op_return? then 'nulldata'
        elsif multisig? then 'multisig'
        else 'nonstandard'
        end
      end

      # --- Data extraction ---

      def pubkey_hash
        return unless p2pkh?

        @bytes.byteslice(3, 20)
      end

      def script_hash
        return unless p2sh?

        @bytes.byteslice(2, 20)
      end

      def op_return_data
        return unless op_return?

        start = @bytes.getbyte(0) == Opcodes::OP_RETURN ? 1 : 2
        Script.new(@bytes.byteslice(start..)).chunks.select(&:data?).map(&:data)
      end

      MAINNET_P2SH_PREFIX = "\x05".b.freeze
      TESTNET_P2SH_PREFIX = "\xc4".b.freeze

      def addresses(network: :mainnet)
        if p2pkh?
          prefix = network == :testnet ? BSV::Primitives::PublicKey::TESTNET_PUBKEY_HASH : BSV::Primitives::PublicKey::MAINNET_PUBKEY_HASH
          [BSV::Primitives::Base58.check_encode(prefix + pubkey_hash)]
        elsif p2sh?
          prefix = network == :testnet ? TESTNET_P2SH_PREFIX : MAINNET_P2SH_PREFIX
          [BSV::Primitives::Base58.check_encode(prefix + script_hash)]
        else
          []
        end
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

      def small_int_opcode?(opcode)
        opcode == Opcodes::OP_0 || opcode.between?(Opcodes::OP_1, Opcodes::OP_16)
      end

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
