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
      # @return [String] the raw script bytes (frozen, binary encoding)
      # @note Scripts are protocol-level immutable; the underlying bytes are
      #   defensively copied + frozen on construction. Downstream callers
      #   that need to build a script incrementally must compose bytes
      #   into a new String and pass it to a fresh +Script.new+.
      attr_reader :bytes

      # @param bytes [String] raw script bytes (default: empty)
      def initialize(bytes = ''.b)
        # Defensive copy + freeze: scripts are immutable in the protocol; freezing
        # @bytes prevents external in-place mutation from staling caches that
        # depend on the script's serialisation (see
        # docs/reference/sighash-cache.md).
        @bytes = bytes.b.dup.freeze
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
      # Supports the canonical aliases +"0"+ (OP_0) and +"-1"+ (OP_1NEGATE).
      # Explicit PUSHDATA sequences (+OP_PUSHDATA1 <len> <hex>+, etc.) are
      # consumed as a unit.
      #
      # @param asm_string [String] space-separated ASM tokens
      # @return [Script]
      def self.from_asm(asm_string)
        buf = ''.b
        tokens = asm_string.split
        i = 0
        while i < tokens.length
          token = tokens[i]

          # Canonical short-hand aliases
          if token == '0'
            buf << [Opcodes::OP_0].pack('C')
            i += 1
            next
          end

          if token == '-1'
            buf << [Opcodes::OP_1NEGATE].pack('C')
            i += 1
            next
          end

          opcode = resolve_opcode(token)

          if [Opcodes::OP_PUSHDATA1, Opcodes::OP_PUSHDATA2, Opcodes::OP_PUSHDATA4].include?(opcode)
            # Explicit PUSHDATA sequence: OP_PUSHDATAn <len> <hex>
            # Consume the following length token and hex token as a unit.
            raise ArgumentError, "#{token} requires <length> <hex> tokens" unless tokens[i + 1] && tokens[i + 2]

            hex_token = tokens[i + 2]
            data = BSV::Primitives::Hex.decode(hex_token.to_s, name: 'ASM PUSHDATA hex token')
            max_len = { Opcodes::OP_PUSHDATA1 => 0xFF, Opcodes::OP_PUSHDATA2 => 0xFFFF, Opcodes::OP_PUSHDATA4 => 0xFFFFFFFF }
            raise ArgumentError, "data too long for #{token}: #{data.bytesize} > #{max_len[opcode]}" if data.bytesize > max_len[opcode]

            case opcode
            when Opcodes::OP_PUSHDATA1
              buf << ([Opcodes::OP_PUSHDATA1, data.bytesize].pack('CC') + data)
            when Opcodes::OP_PUSHDATA2
              buf << ([Opcodes::OP_PUSHDATA2].pack('C') + [data.bytesize].pack('v') + data)
            when Opcodes::OP_PUSHDATA4
              buf << ([Opcodes::OP_PUSHDATA4].pack('C') + [data.bytesize].pack('V') + data)
            end
            i += 3
          elsif opcode
            buf << [opcode].pack('C')
            i += 1
          else
            # Data push — token is hex
            data = BSV::Primitives::Hex.decode(token, name: 'ASM hex token')
            buf << encode_push_data(data)
            i += 1
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
      # Accepts either a raw 20-byte binary hash or a Base58Check address string.
      # When given an address string, the version prefix is validated: +0x00+
      # (mainnet) and +0x6f+ (testnet) are accepted; +0x05+ (P2SH) is rejected
      # with a clear error message.
      #
      # @param pubkey_hash_or_address [String] 20-byte binary pubkey hash, or a
      #   Base58Check address string
      # @return [Script]
      # @raise [ArgumentError] if the argument is not a valid 20-byte hash, if the
      #   address has an unrecognised prefix, or if a P2SH address is supplied
      # @raise [BSV::Primitives::Base58::ChecksumError] if the address checksum is invalid
      def self.p2pkh_lock(pubkey_hash_or_address)
        pubkey_hash = resolve_pubkey_hash(pubkey_hash_or_address)

        buf = [
          Opcodes::OP_DUP,
          Opcodes::OP_HASH160
        ].pack('CC')
        buf << encode_push_data(pubkey_hash)
        buf << [Opcodes::OP_EQUALVERIFY, Opcodes::OP_CHECKSIG].pack('CC')
        new(buf)
      end

      # @api private
      # Resolve a pubkey_hash argument that may be a raw binary hash or a
      # Base58Check address string.
      def self.resolve_pubkey_hash(arg)
        # A 20-byte string is treated as a raw binary hash regardless of
        # encoding — callers commonly pass `"\x00" * 20` which is UTF-8.
        # A valid Base58Check address is always longer than 20 characters
        # (25 raw bytes → ~34 Base58 characters), so this is unambiguous.
        return arg.b if arg.bytesize == 20

        # Otherwise treat as a Base58Check address string.
        decoded = BSV::Primitives::Base58.check_decode(arg, prefix_length: 1)
        prefix = decoded[:prefix]
        data   = decoded[:data]

        p2sh_prefix = "\x05".b
        mainnet_prefix = "\x00".b
        testnet_prefix = "\x6f".b # accepted for testnet interop; no mainnet-only restriction

        if prefix == p2sh_prefix
          raise ArgumentError,
                'P2SH addresses are not supported on BSV; ' \
                'use p2pkh_lock with a P2PKH address or 20-byte hash'
        end

        raise ArgumentError, "unrecognised address prefix: 0x#{prefix.unpack1('H*')}" \
          unless prefix == mainnet_prefix || prefix == testnet_prefix

        raise ArgumentError, 'decoded hash must be 20 bytes' unless data.bytesize == 20

        data
      end
      private_class_method :resolve_pubkey_hash

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
      # The +lock_position+ parameter controls where the locking script is placed
      # relative to the push/drop sequence:
      #
      # - +:'before'+ (default) — lock script appears *before* the data pushes and
      #   drops. Matches the ts-sdk default and the canonical PushDrop layout used
      #   by overlay token protocols.
      #   Structure: +[lock_script] [field0] ... [fieldN] [OP_2DROP...] [OP_DROP?]+
      # - +:'after'+ — lock script appears *after* the drops (legacy behaviour).
      #   Structure: +[field0] ... [fieldN] [OP_2DROP...] [OP_DROP?] [lock_script]+
      #
      # **Breaking change (v0.9):** the default changed from +:'after'+ to
      # +:'before'+ to match the ts-sdk. Callers that relied on the old default
      # must pass +lock_position: :after+ explicitly.
      #
      # @param fields [Array<String>] data payloads to embed (binary strings)
      # @param lock_script [Script] the underlying locking condition (e.g. P2PKH)
      # @param lock_position [Symbol] +:before+ (default) or +:after+
      # @return [Script]
      # @raise [ArgumentError] if fields is empty, lock_script is not a Script,
      #   or lock_position is not +:before+ or +:after+
      def self.pushdrop_lock(fields, lock_script, lock_position: :before)
        raise ArgumentError, 'fields must not be empty' if fields.empty?
        raise ArgumentError, 'lock_script must be a Script' unless lock_script.is_a?(Script)
        raise ArgumentError, "lock_position must be :before or :after, got #{lock_position.inspect}" \
          unless %i[before after].include?(lock_position)

        field_chunks = fields.map { |f| encode_minimally(f.b) }

        drop_chunks = []
        remaining = fields.length
        while remaining > 1
          drop_chunks << Chunk.new(opcode: Opcodes::OP_2DROP)
          remaining -= 2
        end
        drop_chunks << Chunk.new(opcode: Opcodes::OP_DROP) if remaining == 1

        all_chunks = if lock_position == :before
                       lock_script.chunks + field_chunks + drop_chunks
                     else
                       field_chunks + drop_chunks + lock_script.chunks
                     end

        from_chunks(all_chunks)
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
      RPUZZLE_OP_TO_TYPE = RPUZZLE_HASH_OPS.except(:raw).invert.freeze

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

      # Whether the script consists entirely of push-data operations.
      #
      # A script is push-only iff every chunk's opcode is at most +OP_16+
      # (0x60). Used by the script interpreter to enforce the +SIGPUSHONLY+
      # verification flag on unlock scripts.
      #
      # @return [Boolean]
      def push_only?
        chunks.all? { |chunk| chunk.opcode <= Opcodes::OP_16 }
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
      # Detects both +lock_position: :before+ and +lock_position: :after+ layouts:
      #
      # - +:before+: +[lock_chunks...] [field0] ... [fieldN] [OP_2DROP...] [OP_DROP?]+
      # - +:after+:  +[field0] ... [fieldN] [OP_2DROP...] [OP_DROP?] [lock_chunks...]+
      #
      # @return [Boolean]
      def pushdrop?
        pushdrop_layout ? true : false
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
      # After F3.1's fix, the parser absorbs all bytes following a top-level
      # OP_RETURN into a single raw-data chunk. This method re-parses that tail
      # so callers receive one entry per push (including bare opcodes that appear
      # as raw bytes in the tail).
      #
      # @return [Array<String>, nil] array of data pushes, or +nil+ if not OP_RETURN
      def op_return_data
        return unless op_return?

        # Determine where the payload starts (after OP_RETURN or OP_FALSE OP_RETURN)
        start = @bytes.getbyte(0) == Opcodes::OP_RETURN ? 1 : 2

        # Parse the tail bytes as a sub-script to recover individual push items.
        # The tail was stored as a raw-data chunk by parse_chunks; parsing it again
        # yields all the contained push operations.
        #
        # IMPORTANT: disable OP_RETURN termination during re-parse — the tail
        # may legitimately contain 0x6a bytes as data, and we don't want the
        # parser to stop at them.
        tail_bytes = @bytes.byteslice(start, @bytes.bytesize - start)
        return [] if tail_bytes.nil? || tail_bytes.empty?

        tail_script = Script.new(tail_bytes)
        tail_script.send(:parse_chunks, terminate_on_op_return: false).map do |ch|
          ch.data? ? ch.data : [ch.opcode].pack('C')
        end
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
      # Works for both +:before+ and +:after+ lock positions.
      #
      # @return [Array<String>, nil] array of field data, or +nil+ if not PushDrop
      def pushdrop_fields
        layout = pushdrop_layout
        return unless layout

        layout[:field_chunks].map { |ch| decode_minimal_push(ch) }
      end

      # Extract the underlying lock script from a PushDrop script.
      #
      # Works for both +:before+ and +:after+ lock positions.
      #
      # @return [Script, nil] the lock script portion, or +nil+ if not PushDrop
      def pushdrop_lock_script
        layout = pushdrop_layout
        return unless layout

        self.class.from_chunks(layout[:lock_chunks])
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

        # Encode +data+ as the most compact script chunk that still preserves its
        # value when executed.
        #
        # NOTE: A single-byte +[0x00]+ push is intentionally *not* collapsed to
        # OP_0 here. OP_0 pushes an empty byte array, whereas +[0x00]+ pushes a
        # one-byte zero — they are semantically distinct values. The ts-sdk has the
        # same bug (#createMinimallyEncodedScriptChunk conflates them); we fix it
        # locally and plan to raise it upstream.
        def encode_minimally(data)
          len = data.bytesize

          if len.zero?
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

          # Handle OP_UNKNOWN<n> tokens emitted by Chunk#to_asm for unrecognised
          # opcodes — extract the decimal byte value directly.
          if token.start_with?('OP_UNKNOWN')
            suffix = token[10..]
            return nil if suffix.nil? || suffix.empty? || suffix != suffix.to_i.to_s

            n = suffix.to_i
            return n if n.between?(0, 255)

            return nil
          end

          Opcodes.const_get(token.to_sym)
        rescue NameError
          nil
        end
      end

      private

      DROP_OPS = [Opcodes::OP_DROP, Opcodes::OP_2DROP].freeze
      private_constant :DROP_OPS

      # Analyse the chunk array and return a layout hash if this is a PushDrop
      # script, or +nil+ if it is not.
      #
      # Handles both +:before+ (lock first, fields+drops at end) and +:after+
      # (fields+drops first, lock at end) orientations by trying both layouts
      # and returning the first one that satisfies all constraints.
      #
      # Returns +{ field_chunks:, lock_chunks:, position: }+ on success.
      def pushdrop_layout
        c = chunks
        return nil if c.length < 3

        # Locate the first DROP/2DROP.
        drop_start = c.index { |ch| DROP_OPS.include?(ch.opcode) }
        return nil unless drop_start&.positive?

        # Determine the field range by scanning backwards from drop_start.
        # Fields are contiguous data pushes or minimal push opcodes immediately
        # preceding the first DROP/2DROP, regardless of layout orientation.
        field_range_end = drop_start
        field_range_start = drop_start
        while field_range_start.positive? &&
              (c[field_range_start - 1].data? || minimal_push_opcode?(c[field_range_start - 1].opcode))
          field_range_start -= 1
        end
        return nil if field_range_start == drop_start # No fields found

        field_chunks = c[field_range_start...field_range_end]

        # Verify the drop sequence matches the field count exactly.
        num_fields = field_chunks.length
        expected_drops = []
        remaining = num_fields
        while remaining > 1
          expected_drops << Opcodes::OP_2DROP
          remaining -= 2
        end
        expected_drops << Opcodes::OP_DROP if remaining == 1

        drop_end = drop_start + expected_drops.length
        return nil if drop_end > c.length

        actual_drops = c[drop_start...drop_end].map(&:opcode)
        return nil unless actual_drops == expected_drops

        # Determine lock chunks and position based on where the fields begin.
        if field_range_start.zero?
          # ':after' layout — lock is everything after the drops
          lock_chunks = c[drop_end..]
          return nil if lock_chunks.nil? || lock_chunks.empty?

          { field_chunks: field_chunks, lock_chunks: lock_chunks, position: :after }
        else
          # ':before' layout — lock is everything before the fields
          lock_chunks = c[0...field_range_start]
          return nil if lock_chunks.empty?

          { field_chunks: field_chunks, lock_chunks: lock_chunks, position: :before }
        end
      end

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

      # Parse the raw script bytes into an array of {Chunk} objects.
      #
      # Two special behaviours:
      #
      # 1. **OP_RETURN termination** (F3.1): when a top-level OP_RETURN (i.e. not
      #    inside an OP_IF/OP_NOTIF block) is encountered, all remaining bytes are
      #    absorbed as a single raw-data chunk and parsing stops. This matches the
      #    ts-sdk behaviour and correctly handles arbitrary trailing bytes in data
      #    carrier outputs.
      #
      # 2. **Lenient truncation** (F3.16): truncated scripts no longer raise.
      #    Instead, the parser emits a partial chunk array with a trailing
      #    raw-bytes chunk containing whatever bytes remain. This makes +chunks+
      #    and byte-level predicates (+p2pkh?+, +op_return?+, etc.) consistent —
      #    both return a safe "doesn't match any standard type" result for
      #    truncated inputs.
      def parse_chunks(terminate_on_op_return: true)
        result = []
        pos = 0
        raw = @bytes
        conditional_depth = 0

        while pos < raw.bytesize
          opcode = raw.getbyte(pos)
          pos += 1

          # OP_RETURN at top level: absorb all remaining bytes as raw tail data
          # and stop parsing (F3.1).
          if terminate_on_op_return && opcode == Opcodes::OP_RETURN && conditional_depth.zero?
            tail = raw.byteslice(pos, raw.bytesize - pos)
            result << Chunk.new(opcode: opcode, data: tail.empty? ? nil : tail)
            break
          end

          # Track conditional depth for the OP_RETURN termination check above.
          case opcode
          when Opcodes::OP_IF, Opcodes::OP_NOTIF, Opcodes::OP_VERIF, Opcodes::OP_VERNOTIF
            conditional_depth += 1
          when Opcodes::OP_ENDIF
            conditional_depth -= 1 unless conditional_depth.zero?
          end

          if opcode.positive? && opcode <= 0x4b
            available = raw.bytesize - pos
            if available < opcode
              # Truncated: emit whatever bytes are left as a raw chunk (F3.16).
              result << Chunk.new(opcode: opcode, data: raw.byteslice(pos, available))
              break
            end
            data = raw.byteslice(pos, opcode)
            pos += opcode
            result << Chunk.new(opcode: opcode, data: data)
          elsif opcode == Opcodes::OP_PUSHDATA1
            if pos >= raw.bytesize
              # Truncated: length byte missing — emit remaining bytes as raw.
              result << Chunk.new(opcode: opcode, data: raw.byteslice(pos, raw.bytesize - pos))
              break
            end
            len = raw.getbyte(pos)
            pos += 1
            available = raw.bytesize - pos
            if available < len
              result << Chunk.new(opcode: opcode, data: raw.byteslice(pos, available))
              break
            end
            data = raw.byteslice(pos, len)
            pos += len
            result << Chunk.new(opcode: opcode, data: data)
          elsif opcode == Opcodes::OP_PUSHDATA2
            if pos + 2 > raw.bytesize
              result << Chunk.new(opcode: opcode, data: raw.byteslice(pos, raw.bytesize - pos))
              break
            end
            len = raw.byteslice(pos, 2).unpack1('v')
            pos += 2
            available = raw.bytesize - pos
            if available < len
              result << Chunk.new(opcode: opcode, data: raw.byteslice(pos, available))
              break
            end
            data = raw.byteslice(pos, len)
            pos += len
            result << Chunk.new(opcode: opcode, data: data)
          elsif opcode == Opcodes::OP_PUSHDATA4
            if pos + 4 > raw.bytesize
              result << Chunk.new(opcode: opcode, data: raw.byteslice(pos, raw.bytesize - pos))
              break
            end
            len = raw.byteslice(pos, 4).unpack1('V')
            pos += 4
            available = raw.bytesize - pos
            if available < len
              result << Chunk.new(opcode: opcode, data: raw.byteslice(pos, available))
              break
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
