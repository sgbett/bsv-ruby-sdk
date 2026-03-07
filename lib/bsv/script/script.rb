# frozen_string_literal: true

module BSV
  module Script
    # A Bitcoin script — a sequence of opcodes and data pushes.
    #
    # Scripts are the programmable spending conditions attached to transaction
    # outputs (locking scripts) and inputs (unlocking scripts). This class
    # provides construction from multiple formats, type detection, data
    # extraction, and template constructors for standard script types.
    #
    # Follows the SDK's "recognise everything, construct only what's valid"
    # principle — detection methods (e.g. +p2sh?+) work for all script types,
    # but constructors are only provided for types valid on BSV.
    #
    # @example Build a P2PKH locking script
    #   script = BSV::Script::Script.p2pkh_lock(pubkey_hash)
    #   script.type #=> "pubkeyhash"
    #
    # @example Parse from hex and inspect
    #   script = BSV::Script::Script.from_hex('76a914...')
    #   script.p2pkh? #=> true
    #   script.to_asm #=> "OP_DUP OP_HASH160 ... OP_EQUALVERIFY OP_CHECKSIG"
    class Script
      # @return [String] the raw script bytes
      attr_reader :bytes

      # @param bytes [String] raw script bytes (default: empty)
      def initialize(bytes = ''.b)
        @bytes = bytes.b
        @chunks = nil
      end

      # Parse a script from raw binary bytes.
      #
      # @param binary [String] raw script bytes
      # @return [Script]
      def self.from_binary(binary)
        new(binary)
      end

      # Parse a script from a hex string.
      #
      # @param hex [String] hex-encoded script
      # @return [Script]
      def self.from_hex(hex)
        new([hex].pack('H*'))
      end

      # Parse a script from ASM notation.
      #
      # Opcodes are given by name (e.g. +"OP_DUP"+), data pushes as hex.
      #
      # @param asm_string [String] space-separated ASM tokens
      # @return [Script]
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

      # Build a script from an array of {Chunk} objects.
      #
      # @param chunks [Array<Chunk>] script chunks
      # @return [Script]
      def self.from_chunks(chunks)
        buf = chunks.map(&:to_binary).join
        script = new(buf)
        script.instance_variable_set(:@chunks, chunks.dup)
        script
      end

      # Create a new {Builder} for fluent script construction.
      #
      # @return [Builder]
      def self.builder
        Builder.new
      end

      # --- Templates ---

      # Construct an OP_RETURN data carrier script.
      #
      # Uses the safe OP_FALSE OP_RETURN prefix (provably unspendable).
      #
      # @param data_items [Array<String>] one or more data payloads to embed
      # @return [Script]
      def self.op_return(*data_items)
        buf = [Opcodes::OP_FALSE, Opcodes::OP_RETURN].pack('CC')
        data_items.each { |d| buf << encode_push_data(d.b) }
        new(buf)
      end

      # Construct a Pay-to-Public-Key-Hash (P2PKH) locking script.
      #
      # @param pubkey_hash [String] 20-byte public key hash
      # @return [Script]
      # @raise [ArgumentError] if pubkey_hash is not 20 bytes
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

      # Construct a P2PKH unlocking script.
      #
      # @param signature_der [String] DER-encoded signature with sighash byte appended
      # @param pubkey_bytes [String] compressed or uncompressed public key bytes
      # @return [Script]
      def self.p2pkh_unlock(signature_der, pubkey_bytes)
        buf = encode_push_data(signature_der)
        buf << encode_push_data(pubkey_bytes)
        new(buf)
      end

      # Construct a Pay-to-Public-Key (P2PK) locking script.
      #
      # @param pubkey_bytes [String] 33-byte compressed or 65-byte uncompressed public key
      # @return [Script]
      # @raise [ArgumentError] if pubkey_bytes is not 33 or 65 bytes
      def self.p2pk_lock(pubkey_bytes)
        raise ArgumentError, 'pubkey must be 33 or 65 bytes' unless [33, 65].include?(pubkey_bytes.bytesize)

        buf = encode_push_data(pubkey_bytes)
        buf << [Opcodes::OP_CHECKSIG].pack('C')
        new(buf)
      end

      # Construct a P2PK unlocking script.
      #
      # @param signature_der [String] DER-encoded signature with sighash byte appended
      # @return [Script]
      def self.p2pk_unlock(signature_der)
        new(encode_push_data(signature_der))
      end

      # Construct an M-of-N bare multisig locking script.
      #
      # @param required [Integer] number of required signatures (M)
      # @param pubkeys [Array<String>] array of public key byte strings (N keys)
      # @return [Script]
      # @raise [ArgumentError] if M or N is out of range
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

      # Construct a bare multisig unlocking script.
      #
      # @param signatures [Array<String>] DER-encoded signatures with sighash bytes
      # @return [Script]
      def self.p2ms_unlock(*signatures)
        buf = [Opcodes::OP_0].pack('C')
        signatures.each { |sig| buf << encode_push_data(sig.b) }
        new(buf)
      end

      # --- Serialisation ---

      # @return [String] a copy of the raw script bytes
      def to_binary
        @bytes.dup
      end

      # @return [String] hex-encoded script
      def to_hex
        @bytes.unpack1('H*')
      end

      # @return [String] human-readable ASM representation
      def to_asm
        chunks.map(&:to_asm).join(' ')
      end

      # @return [Integer] script length in bytes
      def length
        @bytes.bytesize
      end

      # --- Type predicates ---

      # Whether this is a Pay-to-Public-Key-Hash (P2PKH) script.
      #
      # Pattern: +OP_DUP OP_HASH160 <20 bytes> OP_EQUALVERIFY OP_CHECKSIG+
      #
      # @return [Boolean]
      def p2pkh?
        b = @bytes
        b.bytesize == 25 &&
          b.getbyte(0) == Opcodes::OP_DUP &&
          b.getbyte(1) == Opcodes::OP_HASH160 &&
          b.getbyte(2) == 0x14 &&
          b.getbyte(23) == Opcodes::OP_EQUALVERIFY &&
          b.getbyte(24) == Opcodes::OP_CHECKSIG
      end

      # Whether this is a Pay-to-Script-Hash (P2SH) script.
      #
      # Detection only — P2SH is not valid on BSV, so no constructor is provided.
      # Pattern: +OP_HASH160 <20 bytes> OP_EQUAL+
      #
      # @return [Boolean]
      def p2sh?
        b = @bytes
        b.bytesize == 23 &&
          b.getbyte(0) == Opcodes::OP_HASH160 &&
          b.getbyte(1) == 0x14 &&
          b.getbyte(22) == Opcodes::OP_EQUAL
      end

      # Whether this is an OP_RETURN data carrier script.
      #
      # Matches both +OP_RETURN ...+ and +OP_FALSE OP_RETURN ...+ forms.
      #
      # @return [Boolean]
      def op_return?
        b = @bytes
        (b.bytesize.positive? && b.getbyte(0) == Opcodes::OP_RETURN) ||
          (b.bytesize > 1 && b.getbyte(0) == Opcodes::OP_FALSE && b.getbyte(1) == Opcodes::OP_RETURN)
      end

      # Whether this is a Pay-to-Public-Key (P2PK) script.
      #
      # Pattern: +<pubkey> OP_CHECKSIG+
      #
      # @return [Boolean]
      def p2pk?
        c = chunks
        return false unless c.length == 2 && c[0].data? && c[1].opcode == Opcodes::OP_CHECKSIG

        pubkey = c[0].data
        version = pubkey.getbyte(0)
        ([0x02, 0x03].include?(version) && pubkey.bytesize == 33) ||
          ([0x04, 0x06, 0x07].include?(version) && pubkey.bytesize == 65)
      end

      # Whether this is a bare multisig script.
      #
      # Pattern: +OP_M <pubkey1> ... <pubkeyN> OP_N OP_CHECKMULTISIG+
      #
      # @return [Boolean]
      def multisig?
        c = chunks
        return false if c.length < 3
        return false unless small_int_opcode?(c[0].opcode)
        return false unless small_int_opcode?(c[-2].opcode) && c[-1].opcode == Opcodes::OP_CHECKMULTISIG

        c[1..-3].all?(&:data?)
      end

      # --- Type classification ---

      # Classify the script as a standard type.
      #
      # @return [String] one of +"empty"+, +"pubkeyhash"+, +"pubkey"+,
      #   +"scripthash"+, +"nulldata"+, +"multisig"+, or +"nonstandard"+
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

      # Extract the 20-byte public key hash from a P2PKH script.
      #
      # @return [String, nil] the pubkey hash, or +nil+ if not P2PKH
      def pubkey_hash
        return unless p2pkh?

        @bytes.byteslice(3, 20)
      end

      # Extract the 20-byte script hash from a P2SH script.
      #
      # @return [String, nil] the script hash, or +nil+ if not P2SH
      def script_hash
        return unless p2sh?

        @bytes.byteslice(2, 20)
      end

      # Extract data payloads from an OP_RETURN script.
      #
      # @return [Array<String>, nil] array of data pushes, or +nil+ if not OP_RETURN
      def op_return_data
        return unless op_return?

        start = @bytes.getbyte(0) == Opcodes::OP_RETURN ? 1 : 2
        Script.new(@bytes.byteslice(start..)).chunks.select(&:data?).map(&:data)
      end

      # Derive Bitcoin addresses from this script.
      #
      # Currently supports P2PKH scripts only.
      #
      # @param network [Symbol] +:mainnet+ or +:testnet+
      # @return [Array<String>] array of derived addresses (empty if unsupported type)
      def addresses(network: :mainnet)
        if p2pkh?
          prefix = network == :testnet ? BSV::Primitives::PublicKey::TESTNET_PUBKEY_HASH : BSV::Primitives::PublicKey::MAINNET_PUBKEY_HASH
          [BSV::Primitives::Base58.check_encode(prefix + pubkey_hash)]
        else
          []
        end
      end

      # --- Chunk parsing (lazy) ---

      # Parse the script into an array of {Chunk} objects.
      #
      # Results are cached after first parse.
      #
      # @return [Array<Chunk>] the parsed chunks
      def chunks
        @chunks ||= parse_chunks
      end

      # @param other [Object] the object to compare
      # @return [Boolean] +true+ if both scripts have identical bytes
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
            raise ArgumentError, "truncated script: need #{opcode} data bytes at offset #{pos}" if pos + opcode > raw.bytesize
            data = raw.byteslice(pos, opcode)
            pos += opcode
            result << Chunk.new(opcode: opcode, data: data)
          elsif opcode == Opcodes::OP_PUSHDATA1
            raise ArgumentError, "truncated script: OP_PUSHDATA1 missing length byte at offset #{pos}" if pos >= raw.bytesize
            len = raw.getbyte(pos)
            pos += 1
            data = raw.byteslice(pos, len)
            pos += len
            result << Chunk.new(opcode: opcode, data: data)
          elsif opcode == Opcodes::OP_PUSHDATA2
            raise ArgumentError, "truncated script: OP_PUSHDATA2 needs 2 length bytes at offset #{pos}" if pos + 2 > raw.bytesize
            len = raw.byteslice(pos, 2).unpack1('v')
            pos += 2
            data = raw.byteslice(pos, len)
            pos += len
            result << Chunk.new(opcode: opcode, data: data)
          elsif opcode == Opcodes::OP_PUSHDATA4
            raise ArgumentError, "truncated script: OP_PUSHDATA4 needs 4 length bytes at offset #{pos}" if pos + 4 > raw.bytesize
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
