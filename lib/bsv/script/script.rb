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
        new(BSV::Primitives::Hex.decode(hex, name: 'script hex'))
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
            data = BSV::Primitives::Hex.decode(token, name: 'ASM hex token')
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

      # Construct a PushDrop locking script.
      #
      # Pushes arbitrary data fields onto the stack, then drops them all
      # before the locking condition executes. Used for token protocols
      # where data must be embedded in spendable outputs.
      #
      # Structure: +[field0] [field1] ... [fieldN] [OP_2DROP...] [OP_DROP?] [lock_script]+
      #
      # @param fields [Array<String>] data payloads to embed (binary strings)
      # @param lock_script [Script] the underlying locking condition (e.g. P2PKH)
      # @return [Script]
      # @raise [ArgumentError] if fields is empty or lock_script is not a Script
      def self.pushdrop_lock(fields, lock_script)
        raise ArgumentError, 'fields must not be empty' if fields.empty?
        raise ArgumentError, 'lock_script must be a Script' unless lock_script.is_a?(Script)

        chunks = fields.map { |f| encode_minimally(f.b) }

        remaining = fields.length
        while remaining > 1
          chunks << Chunk.new(opcode: Opcodes::OP_2DROP)
          remaining -= 2
        end
        chunks << Chunk.new(opcode: Opcodes::OP_DROP) if remaining == 1

        chunks.concat(lock_script.chunks)
        from_chunks(chunks)
      end

      # Construct a PushDrop unlocking script.
      #
      # Pass-through wrapper — the data fields are dropped during execution,
      # so the unlocking script just needs to satisfy the underlying lock.
      #
      # @param unlock_script [Script] unlocking script for the underlying condition
      # @return [Script]
      def self.pushdrop_unlock(unlock_script)
        unlock_script
      end

      # Hash type to opcode mapping for RPuzzle scripts.
      RPUZZLE_HASH_OPS = {
        raw: nil,
        sha1: Opcodes::OP_SHA1,
        ripemd160: Opcodes::OP_RIPEMD160,
        sha256: Opcodes::OP_SHA256,
        hash160: Opcodes::OP_HASH160,
        hash256: Opcodes::OP_HASH256
      }.freeze

      # Reverse lookup: opcode → hash type symbol (excludes :raw).
      RPUZZLE_OP_TO_TYPE = RPUZZLE_HASH_OPS.reject { |k, _| k == :raw }.invert.freeze

      # The fixed opcode prefix shared by all RPuzzle locking scripts.
      # OP_OVER OP_3 OP_SPLIT OP_NIP OP_1 OP_SPLIT OP_SWAP OP_SPLIT OP_DROP
      RPUZZLE_PREFIX = [
        Opcodes::OP_OVER, Opcodes::OP_3, Opcodes::OP_SPLIT,
        Opcodes::OP_NIP, Opcodes::OP_1, Opcodes::OP_SPLIT,
        Opcodes::OP_SWAP, Opcodes::OP_SPLIT, Opcodes::OP_DROP
      ].freeze

      # Construct an RPuzzle locking script.
      #
      # RPuzzle enables hash-puzzle-based spending where the spender proves
      # knowledge of the ECDSA K-value (nonce) that produced a signature's
      # R component.
      #
      # @param hash_value [String] the R-value or hash of R-value to lock against
      # @param hash_type [Symbol] one of +:raw+, +:sha1+, +:ripemd160+,
      #   +:sha256+, +:hash160+, +:hash256+
      # @return [Script]
      # @raise [ArgumentError] if hash_type is invalid
      def self.rpuzzle_lock(hash_value, hash_type: :hash160)
        raise ArgumentError, "unknown hash_type: #{hash_type}" unless RPUZZLE_HASH_OPS.key?(hash_type)

        buf = RPUZZLE_PREFIX.pack('C*')
        hash_op = RPUZZLE_HASH_OPS[hash_type]
        buf << [hash_op].pack('C') if hash_op
        buf << encode_push_data(hash_value.b)
        buf << [Opcodes::OP_EQUALVERIFY, Opcodes::OP_CHECKSIG].pack('CC')
        new(buf)
      end

      # Construct an RPuzzle unlocking script.
      #
      # Same wire format as P2PKH: signature + public key.
      #
      # @param signature_der [String] DER-encoded signature with sighash byte
      # @param pubkey_bytes [String] compressed or uncompressed public key bytes
      # @return [Script]
      def self.rpuzzle_unlock(signature_der, pubkey_bytes)
        p2pkh_unlock(signature_der, pubkey_bytes)
      end

      # Construct an OP_CAT locking script.
      #
      # The script concatenates two stack items and compares the result
      # against the expected data. The spender must push two values whose
      # concatenation equals +expected_data+.
      #
      # @param expected_data [String] binary string — the expected result of
      #   concatenating the two unlocking values
      # @return [Script]
      def self.op_cat_lock(expected_data)
        buf = [Opcodes::OP_CAT].pack('C')
        buf << encode_push_data(expected_data.b)
        buf << [Opcodes::OP_EQUAL].pack('C')
        new(buf)
      end

      # Construct an OP_CAT unlocking script.
      #
      # Pushes two data items onto the stack. The locking script's OP_CAT
      # will concatenate them and compare against the expected value.
      #
      # @param data1 [String] binary string — first item (pushed first, deeper on stack)
      # @param data2 [String] binary string — second item (pushed second, top of stack)
      # @return [Script]
      def self.op_cat_unlock(data1, data2)
        buf = encode_push_data(data1.b)
        buf << encode_push_data(data2.b)
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

      # Whether this is a PushDrop script.
      #
      # Detects scripts with one or more data pushes followed by a
      # OP_DROP/OP_2DROP chain and a recognisable locking condition.
      #
      # @return [Boolean]
      def pushdrop?
        c = chunks
        return false if c.length < 3

        # Find the first DROP/2DROP — everything before is data fields
        drop_start = c.index { |ch| [Opcodes::OP_DROP, Opcodes::OP_2DROP].include?(ch.opcode) }
        return false unless drop_start&.positive?

        # All chunks before first drop must be data pushes or minimal push opcodes
        field_chunks = c[0...drop_start]
        return false unless field_chunks.all? { |ch| ch.data? || minimal_push_opcode?(ch.opcode) }

        # Count fields and verify the drop sequence
        num_fields = field_chunks.length
        expected_drops = []
        remaining = num_fields
        while remaining > 1
          expected_drops << Opcodes::OP_2DROP
          remaining -= 2
        end
        expected_drops << Opcodes::OP_DROP if remaining == 1

        drop_end = drop_start + expected_drops.length
        return false if drop_end > c.length

        actual_drops = c[drop_start...drop_end].map(&:opcode)
        return false unless actual_drops == expected_drops

        # Must have at least one chunk after the drops (the lock script)
        drop_end < c.length
      end

      # Whether this is an RPuzzle script.
      #
      # Detects the fixed R-value extraction prefix followed by an optional
      # hash opcode, a data push, OP_EQUALVERIFY, and OP_CHECKSIG.
      #
      # @return [Boolean]
      def rpuzzle?
        c = chunks
        # Minimum: 9 prefix + hash_data + OP_EQUALVERIFY + OP_CHECKSIG = 12
        # With hash op: 13
        return false unless c.length >= 12

        # Verify the 9-opcode prefix
        RPUZZLE_PREFIX.each_with_index do |op, i|
          return false unless c[i].opcode == op
        end

        # After prefix: optional hash op, then data push, OP_EQUALVERIFY, OP_CHECKSIG
        return false unless c[-1].opcode == Opcodes::OP_CHECKSIG
        return false unless c[-2].opcode == Opcodes::OP_EQUALVERIFY
        return false unless c[-3].data?

        # Either exactly 12 chunks (raw) or 13 chunks (with hash op)
        if c.length == 12
          true
        elsif c.length == 13
          RPUZZLE_HASH_OPS.values.compact.include?(c[9].opcode)
        else
          false
        end
      end

      # Whether this is an OP_CAT puzzle script.
      #
      # Pattern: +OP_CAT <expected_data> OP_EQUAL+
      #
      # @return [Boolean]
      def op_cat?
        c = chunks
        c.length == 3 &&
          c[0].opcode == Opcodes::OP_CAT &&
          c[1].data? &&
          c[2].opcode == Opcodes::OP_EQUAL
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
      #   +"scripthash"+, +"nulldata"+, +"multisig"+, +"pushdrop"+,
      #   +"rpuzzle"+, or +"nonstandard"+
      def type
        if @bytes.empty? then 'empty'
        elsif p2pkh? then 'pubkeyhash'
        elsif p2pk? then 'pubkey'
        elsif p2sh? then 'scripthash'
        elsif op_return? then 'nulldata'
        elsif multisig? then 'multisig'
        elsif pushdrop? then 'pushdrop'
        elsif rpuzzle? then 'rpuzzle'
        elsif op_cat? then 'opcat'
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

      # Extract the hash value from an RPuzzle script.
      #
      # @return [String, nil] the locked hash/R-value, or +nil+ if not RPuzzle
      def rpuzzle_hash
        return unless rpuzzle?

        chunks[-3].data
      end

      # Detect the hash type used in an RPuzzle script.
      #
      # @return [Symbol, nil] the hash type (e.g. +:hash160+, +:raw+), or +nil+ if not RPuzzle
      def rpuzzle_hash_type
        return unless rpuzzle?

        chunks.length == 12 ? :raw : RPUZZLE_OP_TO_TYPE[chunks[9].opcode]
      end

      # Extract the embedded data fields from a PushDrop script.
      #
      # @return [Array<String>, nil] array of field data, or +nil+ if not PushDrop
      def pushdrop_fields
        return unless pushdrop?

        c = chunks
        drop_start = c.index { |ch| [Opcodes::OP_DROP, Opcodes::OP_2DROP].include?(ch.opcode) }
        c[0...drop_start].map { |ch| decode_minimal_push(ch) }
      end

      # Extract the underlying lock script from a PushDrop script.
      #
      # @return [Script, nil] the lock script portion, or +nil+ if not PushDrop
      def pushdrop_lock_script
        return unless pushdrop?

        c = chunks
        drop_start = c.index { |ch| [Opcodes::OP_DROP, Opcodes::OP_2DROP].include?(ch.opcode) }
        num_fields = drop_start
        num_drops = (num_fields / 2) + (num_fields.odd? ? 1 : 0)
        lock_start = drop_start + num_drops
        self.class.from_chunks(c[lock_start..])
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

        def encode_minimally(data)
          len = data.bytesize

          if len.zero? || (len == 1 && data.getbyte(0).zero?)
            Chunk.new(opcode: Opcodes::OP_0)
          elsif len == 1 && data.getbyte(0).between?(1, 16)
            Chunk.new(opcode: 0x50 + data.getbyte(0))
          elsif len == 1 && data.getbyte(0) == 0x81
            Chunk.new(opcode: Opcodes::OP_1NEGATE)
          elsif len <= 0x4b
            Chunk.new(opcode: len, data: data)
          elsif len <= 0xff
            Chunk.new(opcode: Opcodes::OP_PUSHDATA1, data: data)
          elsif len <= 0xffff
            Chunk.new(opcode: Opcodes::OP_PUSHDATA2, data: data)
          else
            Chunk.new(opcode: Opcodes::OP_PUSHDATA4, data: data)
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

      def minimal_push_opcode?(opcode)
        opcode == Opcodes::OP_0 ||
          opcode == Opcodes::OP_1NEGATE ||
          opcode.between?(Opcodes::OP_1, Opcodes::OP_16)
      end

      def decode_minimal_push(chunk)
        return chunk.data if chunk.data?

        case chunk.opcode
        when Opcodes::OP_0 then ''.b
        when Opcodes::OP_1NEGATE then "\x81".b
        when Opcodes::OP_1..Opcodes::OP_16
          [chunk.opcode - 0x50].pack('C')
        end
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
            if pos + len > raw.bytesize
              raise ArgumentError,
                    "truncated script: OP_PUSHDATA1 needs #{len} data bytes at offset #{pos}, got #{raw.bytesize - pos}"
            end

            data = raw.byteslice(pos, len)
            pos += len
            result << Chunk.new(opcode: opcode, data: data)
          elsif opcode == Opcodes::OP_PUSHDATA2
            raise ArgumentError, "truncated script: OP_PUSHDATA2 needs 2 length bytes at offset #{pos}" if pos + 2 > raw.bytesize

            len = raw.byteslice(pos, 2).unpack1('v')
            pos += 2
            if pos + len > raw.bytesize
              raise ArgumentError,
                    "truncated script: OP_PUSHDATA2 needs #{len} data bytes at offset #{pos}, got #{raw.bytesize - pos}"
            end

            data = raw.byteslice(pos, len)
            pos += len
            result << Chunk.new(opcode: opcode, data: data)
          elsif opcode == Opcodes::OP_PUSHDATA4
            raise ArgumentError, "truncated script: OP_PUSHDATA4 needs 4 length bytes at offset #{pos}" if pos + 4 > raw.bytesize

            len = raw.byteslice(pos, 4).unpack1('V')
            pos += 4
            if pos + len > raw.bytesize
              raise ArgumentError,
                    "truncated script: OP_PUSHDATA4 needs #{len} data bytes at offset #{pos}, got #{raw.bytesize - pos}"
            end

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
