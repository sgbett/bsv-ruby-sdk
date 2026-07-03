# frozen_string_literal: true

module BSV
  module Transaction
    # A Bitcoin transaction: a collection of inputs consuming previous outputs
    # and producing new outputs.
    #
    # Supports construction, binary/hex serialisation, BIP-143 sighash
    # computation (with FORKID), signing, script verification, and fee
    # estimation.
    #
    # @note Not thread-safe. Direct mutation of {#inputs} / {#outputs} arrays
    #   (e.g. `tx.inputs << input`) bypasses the cache-invalidation contract
    #   and may produce silently invalid sighashes. Use {#add_input} /
    #   {#add_output} and the documented setter surface, or call
    #   {#invalidate_caches} after direct mutation. See
    #   {file:docs/reference/sighash-cache.md}.
    #
    # @example Build, sign, and serialise a transaction
    #   tx = BSV::Transaction::Tx.new
    #   tx.add_input(input)
    #   tx.add_output(output)
    #   tx.sign(0, private_key)
    #   tx.to_hex #=> "0100000001..."
    class Tx
      # Estimated size of an unsigned P2PKH input in bytes.
      UNSIGNED_P2PKH_INPUT_SIZE = 148

      # Lookup table for benford_number calculation.
      # we want float values for log10(1 + (1.0 / i)) for the 9 integers 0 < i < 10
      # in ruby this becomes: (1..9).to_a.collect{|d| Math.log10(1 + (1.0 / d)) }
      LOG10_RECIPROCAL_D_VALUES_1TO9 = [0.3010299956639812,
                                        0.17609125905568124,
                                        0.12493873660829993,
                                        0.09691001300805642,
                                        0.07918124604762482,
                                        0.06694678963061322,
                                        0.05799194697768673,
                                        0.05115252244738129,
                                        0.04575749056067514].freeze

      # @return [Integer] transaction version number
      attr_reader :version

      # @return [Integer] lock time (block height or Unix timestamp)
      attr_reader :lock_time

      # @return [Array<TransactionInput>] transaction inputs
      attr_reader :inputs

      # @return [Array<TransactionOutput>] transaction outputs
      attr_reader :outputs

      # @return [MerklePath, nil] BRC-74 merkle path (for BEEF serialisation)
      attr_accessor :merkle_path

      # @param version [Integer] transaction version (default: 1)
      # @param lock_time [Integer] lock time (default: 0)
      def initialize(version: 1, lock_time: 0)
        @version = version
        @lock_time = lock_time
        @inputs = []
        @outputs = []
        @merkle_path = nil
      end

      # Append a transaction input.
      #
      # Idempotent on re-add: calling +add_input(x)+ twice with the same input
      # on the same +Transaction::Tx+ returns +self+ on the second call without
      # appending a duplicate or invalidating caches. Raises +ArgumentError+
      # if the input is already attached to a different +Transaction::Tx+.
      #
      # @param input [Transaction::TransactionInput] the input to add
      # @return [self] for chaining
      # @raise [ArgumentError] if the input is already attached to a different
      #   Tx instance. Sharing across Tx instances is anti-idiomatic;
      #   construct a fresh instance per Tx. See
      #   {file:docs/reference/sighash-cache.md#one-owner}.
      def add_input(input)
        existing_owner = input.instance_variable_get(:@owning_tx)
        if existing_owner
          return self if existing_owner.equal?(self)

          raise ArgumentError,
                "TransactionInput #{input.dtxid_hex}:#{input.prev_tx_out_index} is already attached to a Tx"
        end

        input.instance_variable_set(:@owning_tx, self)
        @inputs << input
        # Avoid the O(N+M) rebind walk inside invalidate_caches — the new
        # input's backref was just set above and every existing input/output
        # was rebound when it was originally added. clear_caches is O(1).
        clear_caches
        self
      end

      # Append a transaction output.
      #
      # Idempotent on re-add: calling +add_output(x)+ twice with the same output
      # on the same +Transaction::Tx+ returns +self+ on the second call without
      # appending a duplicate or invalidating caches. Raises +ArgumentError+
      # if the output is already attached to a different +Transaction::Tx+.
      #
      # @param output [Transaction::TransactionOutput] the output to add
      # @return [self] for chaining
      # @raise [ArgumentError] if the output is already attached to a different
      #   Tx instance. Sharing across Tx instances is anti-idiomatic;
      #   construct a fresh instance per Tx. See
      #   {file:docs/reference/sighash-cache.md#one-owner}.
      def add_output(output)
        existing_owner = output.instance_variable_get(:@owning_tx)
        if existing_owner
          return self if existing_owner.equal?(self)

          asm_fragment = output.locking_script&.to_asm || '<nil locking_script>'
          asm_fragment = "#{asm_fragment[0, 40]}..." if asm_fragment.length > 40
          raise ArgumentError,
                "TransactionOutput (#{asm_fragment}) is already attached to a Tx"
        end

        output.instance_variable_set(:@owning_tx, self)
        @outputs << output
        # Avoid the O(N+M) rebind walk inside invalidate_caches — the new
        # output's backref was just set above and every existing input/output
        # was rebound when it was originally added. clear_caches is O(1).
        clear_caches
        self
      end

      # Invalidate all cached state on this transaction (sighash components,
      # wire serialisation, etc.) AND restore the +@owning_tx+ backref on every
      # current input and output. This is what makes the escape hatch complete:
      # if a caller appended an input/output via direct array mutation
      # (bypassing +add_input+ / +add_output+), the new struct's backref is nil
      # and future +sequence=+ / +locking_script=+ / etc. setters would not
      # bubble invalidation up. After +invalidate_caches+, the backref is
      # rebound so subsequent setter mutations flow through correctly.
      #
      # Raises +ArgumentError+ if any input or output is already attached to a
      # different +Transaction::Tx+ — matches the cross-Tx rebind contract of
      # +add_input+ / +add_output+.
      #
      # @example After mutating the inputs array directly
      #   tx.inputs << input             # bypasses the documented setter surface
      #   tx.invalidate_caches           # clears all cache layers + rebinds @owning_tx
      #   input.sequence = 42            # now invalidates correctly
      #   tx.verify(...)                 # safe
      #
      # @note Rarely needed. Normal mutation through the documented setter
      #   surface (input.sequence=, output.satoshis=, etc.) invalidates the
      #   right cache slices automatically. This method is an escape hatch
      #   for code that mutates @inputs / @outputs through unsupported paths.
      #   See {file:docs/reference/sighash-cache.md#escape-hatch}.
      #
      # @return [self] for chaining
      # @raise [ArgumentError] if any input or output is attached to a different
      #   Tx instance
      def invalidate_caches
        rebind_owning_tx!
        clear_caches
        self
      end

      # Called by +#dup+ and +#clone+. Deep-dups +@inputs+ and +@outputs+ so that
      # the copy and the original do not share mutable input/output state. Rebinds
      # +@owning_tx+ on each copied struct to +self+ (the new transaction). Resets
      # all cache ivars directly so the dup does not share mutable cache state
      # (especially +@hash_outputs_single+, a Hash) with the original.
      #
      # This closes the hazard at +beef.rb:703,707+ where a shallow dup would leave
      # the copied inputs/outputs pointing at the original transaction's cache.
      #
      # Note: we cannot delegate to +invalidate_caches+ here because that method
      # calls +Hash#clear+ on +@hash_outputs_single+, which would mutate the
      # shared Hash and evict the *original*'s per-index cache too. Direct
      # +ivar = nil+ assignments on +self+ leave the original untouched.
      def initialize_copy(other)
        super
        @inputs = @inputs.map do |i|
          dup_input = i.dup
          dup_input.instance_variable_set(:@owning_tx, self)
          dup_input
        end
        @outputs = @outputs.map do |o|
          dup_output = o.dup
          dup_output.instance_variable_set(:@owning_tx, self)
          dup_output
        end
        @to_binary = nil
        @wtxid = nil
        @hash_prevouts = nil
        @hash_sequence = nil
        @hash_outputs_all = nil
        @hash_outputs_single = nil
      end

      # --- Serialisation ---

      # Serialise the transaction to its binary wire format.
      #
      # @note Memoised; see {file:docs/reference/sighash-cache.md} for the invalidation contract.
      # @return [String] raw transaction bytes (binary encoding, frozen)
      def to_binary
        @to_binary ||= begin
          buf = [@version].pack('V')
          buf << VarInt.encode(@inputs.length)
          @inputs.each { |i| buf << i.to_binary }
          buf << VarInt.encode(@outputs.length)
          @outputs.each { |o| buf << o.to_binary }
          buf << [@lock_time].pack('V')
          buf.b.freeze
        end
      end

      # Serialise the transaction to a hex string.
      #
      # @return [String] hex-encoded transaction
      def to_hex
        to_binary.unpack1('H*')
      end

      # Serialise the transaction in Extended Format (BRC-30).
      #
      # EF embeds source satoshis and source locking scripts in each input,
      # allowing ARC to validate sighashes without fetching parent transactions.
      #
      # Source data is resolved in priority order:
      # 1. Explicit +source_satoshis+ / +source_locking_script+ on the input.
      # 2. Derived from +input.source_transaction.outputs[input.prev_tx_out_index]+.
      #
      # Source fields on input objects are never mutated — derivation happens on
      # each call, so calling +to_ef+ twice produces identical output.
      #
      # @return [String] raw EF transaction bytes
      # @raise [ArgumentError] if any input cannot supply source_satoshis or
      #   source_locking_script via either mechanism
      def to_ef
        buf = [@version].pack('V')
        buf << "\x00\x00\x00\x00\x00\xEF".b
        buf << VarInt.encode(@inputs.length)
        @inputs.each_with_index do |input, idx|
          source_output = ef_source_output(input, idx)

          satoshis = input.source_satoshis || source_output.satoshis
          locking_script = input.source_locking_script || source_output.locking_script

          buf << input.to_binary
          buf << [satoshis].pack('Q<')
          lock_bytes = locking_script.to_binary
          buf << VarInt.encode(lock_bytes.bytesize)
          buf << lock_bytes
        end
        buf << VarInt.encode(@outputs.length)
        @outputs.each { |o| buf << o.to_binary }
        buf << [@lock_time].pack('V')
        buf
      end

      # Serialise the transaction in Extended Format as a hex string.
      #
      # @return [String] hex-encoded EF transaction
      def to_ef_hex
        to_ef.unpack1('H*')
      end

      # Deserialise a transaction from binary data.
      #
      # @param data [String] raw binary transaction
      # @return [Transaction::Tx] the parsed transaction
      def self.from_binary(data)
        raise ArgumentError, "truncated transaction: need at least 10 bytes, got #{data.bytesize}" if data.bytesize < 10

        offset = 0

        version = data.byteslice(offset, 4).unpack1('V')
        offset += 4

        tx = new(version: version)

        input_count, vi_size = VarInt.decode(data, offset)
        offset += vi_size
        input_count.times do
          input, consumed = TransactionInput.from_binary(data, offset)
          tx.add_input(input)
          offset += consumed
        end

        output_count, vi_size = VarInt.decode(data, offset)
        offset += vi_size
        output_count.times do
          output, consumed = TransactionOutput.from_binary(data, offset)
          tx.add_output(output)
          offset += consumed
        end

        if data.bytesize < offset + 4
          raise ArgumentError, "truncated transaction: need 4 bytes for lock_time at offset #{offset}, got #{data.bytesize - offset}"
        end

        tx.instance_variable_set(:@lock_time, data.byteslice(offset, 4).unpack1('V'))
        tx
      end

      # Deserialise a transaction from a hex string.
      #
      # @param hex [String] hex-encoded transaction
      # @return [Transaction::Tx] the parsed transaction
      def self.from_hex(hex)
        from_binary(BSV::Primitives::Hex.decode(hex, name: 'transaction hex'))
      end

      # Deserialise a transaction from Extended Format (BRC-30) binary data.
      #
      # @param data [String] raw EF binary
      # @return [Transaction::Tx] the parsed transaction with source data on inputs
      # @raise [ArgumentError] if the EF marker is invalid
      def self.from_ef(data)
        raise ArgumentError, "truncated EF transaction: need at least 10 bytes, got #{data.bytesize}" if data.bytesize < 10

        offset = 0

        version = data.byteslice(offset, 4).unpack1('V')
        offset += 4

        marker = data.byteslice(offset, 6)
        raise ArgumentError, 'invalid EF marker' unless marker == "\x00\x00\x00\x00\x00\xEF".b

        offset += 6

        tx = new(version: version)

        input_count, vi_size = VarInt.decode(data, offset)
        offset += vi_size
        input_count.times do
          input, consumed = TransactionInput.from_binary(data, offset)
          tx.add_input(input)
          offset += consumed

          if data.bytesize < offset + 8
            remaining = data.bytesize - offset
            raise ArgumentError, "truncated EF input: need 8 bytes for source_satoshis at offset #{offset}, got #{remaining}"
          end

          input.source_satoshis = data.byteslice(offset, 8).unpack1('Q<')
          offset += 8

          lock_len, vi_size = VarInt.decode(data, offset)
          offset += vi_size
          if lock_len.positive?
            input.source_locking_script = BSV::Script::Script.from_binary(data.byteslice(offset, lock_len))
            offset += lock_len
          end
        end

        output_count, vi_size = VarInt.decode(data, offset)
        offset += vi_size
        output_count.times do
          output, consumed = TransactionOutput.from_binary(data, offset)
          tx.add_output(output)
          offset += consumed
        end

        if data.bytesize < offset + 4
          remaining = data.bytesize - offset
          raise ArgumentError, "truncated EF transaction: need 4 bytes for lock_time at offset #{offset}, got #{remaining}"
        end

        tx.instance_variable_set(:@lock_time, data.byteslice(offset, 4).unpack1('V'))
        tx
      end

      # Deserialise a transaction from an Extended Format hex string.
      #
      # @param hex [String] hex-encoded EF transaction
      # @return [Transaction::Tx] the parsed transaction with source data on inputs
      def self.from_ef_hex(hex)
        from_ef(BSV::Primitives::Hex.decode(hex, name: 'EF transaction hex'))
      end

      # Deserialise a transaction from binary data at a given offset,
      # returning the transaction and the number of bytes consumed.
      #
      # @param data [String] binary data containing the transaction
      # @param offset [Integer] byte offset to start reading from
      # @return [Array(Transaction::Tx, Integer)] the transaction and bytes consumed
      def self.from_binary_with_offset(data, offset = 0)
        if data.bytesize < offset + 10
          raise ArgumentError, "truncated transaction: need at least 10 bytes at offset #{offset}, got #{data.bytesize - offset}"
        end

        start = offset

        version = data.byteslice(offset, 4).unpack1('V')
        offset += 4

        tx = new(version: version)

        input_count, vi_size = VarInt.decode(data, offset)
        offset += vi_size
        input_count.times do
          input, consumed = TransactionInput.from_binary(data, offset)
          tx.add_input(input)
          offset += consumed
        end

        output_count, vi_size = VarInt.decode(data, offset)
        offset += vi_size
        output_count.times do
          output, consumed = TransactionOutput.from_binary(data, offset)
          tx.add_output(output)
          offset += consumed
        end

        if data.bytesize < offset + 4
          raise ArgumentError, "truncated transaction: need 4 bytes for lock_time at offset #{offset}, got #{data.bytesize - offset}"
        end

        tx.instance_variable_set(:@lock_time, data.byteslice(offset, 4).unpack1('V'))
        offset += 4

        [tx, offset - start]
      end

      # --- BEEF convenience methods ---

      # Serialise this transaction (with its ancestry chain and merkle proofs)
      # into a BEEF V1 binary bundle (BRC-62), the default format for ARC and
      # the reference TS SDK.
      #
      # Walks the `source_transaction` references on inputs to collect ancestors.
      # Transactions with a `merkle_path` are treated as proven leaves — their
      # ancestors are not traversed further.
      #
      # Proven ancestors that share a block are combined into a single BUMP per
      # block, then trimmed via {MerklePath#extract} so the serialised bundle
      # carries only the +txid: true+-flagged leaves that correspond to
      # transactions in this BEEF. This prevents "phantom" txid leaves carried
      # over from a shared {LocalProofStore} entry (issue #302) and also
      # shrinks the BEEF by dropping intermediate sibling hashes that are no
      # longer needed.
      #
      # Ancestor +merkle_path+ objects are not mutated: paths are deep-copied
      # before any combine/trim work.
      #
      # @return [String] raw BEEF V1 binary
      # @raise [ArgumentError] if an ancestor's merkle_path does not actually
      #   contain that transaction's txid, or if the cleaned BUMP's root does
      #   not match the source root (both indicate corrupt proof data)
      def to_beef
        beef = Beef.new
        ancestors = collect_ancestors

        bump_index_by_height = build_beef_bumps(beef, ancestors)
        BSV.logger&.debug do
          proven = ancestors.count(&:merkle_path)
          "[Tx] BEEF: #{ancestors.length} ancestors, #{proven} proven " \
            "across #{bump_index_by_height.length} block heights"
        end

        ancestors.each do |tx|
          entry = if tx.merkle_path
                    Beef::ProvenTxEntry.new(
                      transaction: tx,
                      bump_index: bump_index_by_height.fetch(tx.merkle_path.block_height)
                    )
                  else
                    Beef::RawTxEntry.new(transaction: tx)
                  end
          beef.transactions << entry
        end

        beef.to_binary
      end

      # Serialise this transaction to a BEEF V2 hex string.
      #
      # @return [String] hex-encoded BEEF
      def to_beef_hex
        to_beef.unpack1('H*')
      end

      # Parse a BEEF binary bundle and return the subject transaction with
      # full ancestry wired, including late-bound BUMP attachment.
      #
      # For Atomic BEEFs (BRC-95), the subject transaction is identified by
      # the embedded +subject_wtxid+ field. For plain BEEFs, the last
      # transaction with a raw tx entry is used as the subject.
      #
      # Uses +find_atomic_transaction+ so that FORMAT_RAW_TX ancestors whose
      # wtxid appears as a leaf in a separately-stored BUMP get their
      # +merkle_path+ wired correctly — a gap not covered by the initial
      # +wire_source_transactions+ pass in +Beef.from_binary+.
      #
      # @param data [String] raw BEEF binary
      # @return [Transaction::Tx, nil] the subject transaction with ancestry wired,
      #   or nil if the BEEF is empty or contains no raw transaction entries
      def self.from_beef(data)
        beef = Beef.from_binary(data)
        subject_wtxid = beef.subject_wtxid ||
                        beef.transactions.reverse.find { |bt| !bt.is_a?(Beef::TxidOnlyEntry) }&.wtxid
        return nil unless subject_wtxid

        beef.find_atomic_transaction(subject_wtxid)
      end

      # Parse a BEEF hex string and return the subject transaction.
      #
      # @param hex [String] hex-encoded BEEF
      # @return [Transaction::Tx, nil] the subject transaction with ancestry wired,
      #   or nil if the BEEF is empty or contains no raw transaction entries
      def self.from_beef_hex(hex)
        from_beef(BSV::Primitives::Hex.decode(hex, name: 'BEEF hex'))
      end

      # --- Transaction ID ---

      # Wire-order transaction ID (raw SHA-256d of the serialised tx).
      #
      # Used by BEEF, BUMPs, and merkle paths, which all work in wire byte order
      # to match {TransactionInput#prev_wtxid}.
      #
      # @note Memoised; see {file:docs/reference/sighash-cache.md} for the invalidation contract.
      # @return [String] 32-byte transaction ID in wire byte order
      def wtxid
        @wtxid ||= begin
          id = BSV::Primitives::Digest.sha256d(to_binary)
          BSV.logger&.debug { "[Tx] wtxid computed (dtxid=#{id.reverse.unpack1('H*')})" }
          id.freeze
        end
      end

      # The transaction ID as a hex string (display byte order).
      #
      # @return [String] 64-char hex-encoded transaction ID (display order)
      def txid_hex
        wtxid.reverse.unpack1('H*')
      end

      # Display-order transaction ID as a hex string.
      #
      # Mirrors the wallet gem's +DisplayTxid+ pattern. +dtxid+ always returns
      # a 64-char hex string suitable for JSON and UI boundaries.
      #
      # @return [String] hex-encoded transaction ID (display order)
      alias dtxid txid_hex

      # Display-order transaction ID as a hex string (alias for {#dtxid}).
      #
      # @return [String] hex-encoded transaction ID (display order)
      alias dtxid_hex txid_hex

      # --- Sighash (BIP-143 with FORKID) ---

      # Build the BIP-143 sighash preimage for an input.
      #
      # Only SIGHASH_FORKID types are supported (BSV requirement).
      #
      # @param input_index [Integer] the input to compute the preimage for
      # @param sighash_type [Integer] sighash flags (default: ALL|FORKID)
      # @param subscript [Script::Script, nil] override locking script for the input
      # @return [String] the raw preimage bytes (hash this to get the sighash)
      # @raise [ArgumentError] if sighash_type does not include FORKID
      def sighash_preimage(input_index, sighash_type = Sighash::ALL_FORK_ID, subscript: nil)
        raise ArgumentError, 'only SIGHASH_FORKID types are supported' unless sighash_type & Sighash::FORK_ID != 0

        input = @inputs[input_index]
        raise ArgumentError, "no input at index #{input_index}" if input.nil?

        # Resolve source data from wired source_transaction when not explicitly set.
        if input.source_transaction
          source_output = input.source_transaction.outputs[input.prev_tx_out_index]
          if source_output
            input.source_satoshis       ||= source_output.satoshis
            input.source_locking_script ||= source_output.locking_script
          end
        end

        if input.source_satoshis.nil?
          raise ArgumentError,
                "input #{input_index} has nil source_satoshis — " \
                'set it or wire source_transaction before computing sighash'
        end

        unless subscript || input.source_locking_script
          raise ArgumentError,
                "input #{input_index} has nil source_locking_script — " \
                'set it or wire source_transaction before computing sighash'
        end

        base_type = sighash_type & Sighash::MASK
        anyone = sighash_type.anybits?(Sighash::ANYONE_CAN_PAY)

        # 1. nVersion (4 LE)
        buf = [@version].pack('V')

        # 2. hashPrevouts
        buf << hash_prevouts(anyone)

        # 3. hashSequence
        buf << hash_sequence(anyone, base_type)

        # 4. outpoint of this input (32 + 4)
        buf << input.outpoint_binary

        # 5. scriptCode of this input (varint + script)
        script_bytes = (subscript || input.source_locking_script).to_binary
        buf << VarInt.encode(script_bytes.bytesize)
        buf << script_bytes

        # 6. value of this input (8 LE)
        buf << [input.source_satoshis].pack('Q<')

        # 7. nSequence of this input (4 LE)
        buf << [input.sequence].pack('V')

        # 8. hashOutputs
        buf << hash_outputs(base_type, input_index)

        # 9. nLockTime (4 LE)
        buf << [@lock_time].pack('V')

        # 10. sighash type (4 LE) — includes FORKID flag
        buf << [sighash_type].pack('V')

        BSV.logger&.debug do
          hp = buf.byteslice(4, 32).unpack1('H*')
          hs = buf.byteslice(36, 32).unpack1('H*')
          op = input.outpoint_binary.unpack1('H*')
          sc = script_bytes.unpack1('H*')
          ho = buf.byteslice(-40, 32).unpack1('H*')
          "[Sighash] input=#{input_index} type=0x#{format('%02x', sighash_type)} " \
            "version=#{@version} hashPrevouts=#{hp} hashSequence=#{hs} " \
            "outpoint=#{op} scriptCode=#{sc[0, 40]}#{'...' if sc.length > 40} " \
            "value=#{input.source_satoshis} seq=#{input.sequence} " \
            "hashOutputs=#{ho} locktime=#{@lock_time}"
        end

        buf
      end

      # Compute the BIP-143 sighash digest for an input (double-SHA-256 of the preimage).
      #
      # @param input_index [Integer] the input to compute the sighash for
      # @param sighash_type [Integer] sighash flags (default: ALL|FORKID)
      # @param subscript [Script::Script, nil] override locking script for the input
      # @return [String] 32-byte sighash digest
      def sighash(input_index, sighash_type = Sighash::ALL_FORK_ID, subscript: nil)
        digest = BSV::Primitives::Digest.sha256d(sighash_preimage(input_index, sighash_type, subscript: subscript))
        BSV.logger&.debug { "[Sighash] digest=#{digest.unpack1('H*')}" }
        digest
      end

      # --- Signing ---

      # Sign a single input with a private key (P2PKH).
      #
      # Computes the sighash, signs it, and sets the unlocking script on the input.
      #
      # @param input_index [Integer] the input to sign
      # @param private_key [Primitives::PrivateKey] the signing key
      # @param sighash_type [Integer] sighash flags (default: ALL|FORKID)
      # @return [self] for chaining
      def sign(input_index, private_key, sighash_type = Sighash::ALL_FORK_ID)
        # F4.9: validate outputs have satoshis before signing — a nil satoshis
        # value would produce a corrupt sighash preimage.
        @outputs.each_with_index do |output, idx|
          raise ArgumentError, "output #{idx} has nil satoshis — set before signing" if output.satoshis.nil?
        end

        hash = sighash(input_index, sighash_type)
        signature = private_key.sign(hash)
        sig_with_hashtype = signature.to_der + [sighash_type].pack('C')
        pubkey_bytes = private_key.public_key.compressed

        @inputs[input_index].unlocking_script =
          BSV::Script::Script.p2pkh_unlock(sig_with_hashtype, pubkey_bytes)
        self
      end

      # Sign all unsigned inputs.
      #
      # For each input without an unlocking script: if the input has an
      # {UnlockingScriptTemplate}, delegates to it; otherwise falls back
      # to P2PKH signing with the given private key.
      #
      # @param private_key [Primitives::PrivateKey, nil] fallback signing key
      # @param sighash_type [Integer] sighash flags (default: ALL|FORKID)
      # @return [self] for chaining
      def sign_all(private_key = nil, sighash_type = Sighash::ALL_FORK_ID)
        @inputs.each_with_index do |input, index|
          next if input.unlocking_script

          if input.unlocking_script_template
            input.unlocking_script = input.unlocking_script_template.sign(self, index)
          elsif private_key
            sign(index, private_key, sighash_type)
          end
        end
        self
      end

      # --- Script verification ---

      # Verify the scripts of a single input using the interpreter.
      #
      # @param index [Integer] the input index to verify
      # @return [Boolean] true if the scripts evaluate successfully
      def verify_input(index)
        input = @inputs[index]
        BSV::Script::Interpreter.verify(
          tx: self,
          input_index: index,
          unlock_script: input.unlocking_script,
          lock_script: input.source_locking_script,
          satoshis: input.source_satoshis
        )
      end

      # --- SPV verification ---

      # Perform full SPV verification of this transaction and its ancestry.
      #
      # Uses a queue-based approach (matching TS/Go SDKs) to walk the
      # transaction ancestry chain:
      #
      # 1. If a transaction has a merkle path that validates against the chain
      #    tracker, it is marked verified (inputs are not re-checked).
      # 2. Otherwise, each input's scripts are executed via the interpreter,
      #    and source transactions are enqueued for verification.
      # 3. Optionally validates that the root transaction's fee meets the
      #    provided fee model.
      # 4. Checks that total outputs do not exceed total inputs.
      #
      # == Semantic Divergences from Reference SDKs
      #
      # This implementation raises +VerificationError+ for all failure modes.
      # The TypeScript and Python SDKs return +false+ for script failures and
      # output overflow. The Go SDK propagates errors (not booleans) for script
      # failures, aligning with the Ruby approach.
      #
      # Rationale: raising provides structured error information (+#code+,
      # +#message+, +#cause+) that a boolean cannot convey. Consumers can
      # rescue +VerificationError+ and inspect +#code+ for specifics.
      #
      # Divergence summary:
      # - +:output_overflow+ — Ruby raises; TS/Python return +false+; Go omits the check
      # - +:script_failure+ — Ruby raises; TS/Python return +false+; Go also propagates errors
      # - +:missing_source+ — Ruby raises; consistent with TS/Go/Python (all raise/error)
      # - +verified:+ kwarg — Ruby-only; no equivalent seam exists in the TS, Go, or Python SDKs.
      #   This is a novel Ruby-side extension: a bidirectional wtxid-dedup Hash that the caller
      #   can seed (short-circuit ancestors already verified) and read after +verify+ returns
      #   (populate a persistent verification cache). See {file:docs/reference/verify-kwarg.md}.
      #   The reference SDKs repeat the full walk every time +verify+ is called.
      #
      # @param chain_tracker [Transaction::ChainTracker] chain tracker for merkle root validation
      # @param fee_model [FeeModel, nil] optional fee model to validate the root transaction's fee
      # @param verified [Hash{String => Boolean}, nil] bidirectional wtxid dedup Hash.
      #   Keys are 32-byte wire-order binary wtxids (not hex). Values are presence-only —
      #   the SDK treats any truthy value as "already verified" and writes +true+ for wtxids
      #   it walks. Callers use this three ways:
      #
      #   - **Pre-seed** (short-circuit): pass a Hash pre-populated with wtxids you have
      #     verified in an earlier session. Their subtrees are skipped.
      #   - **Post-read** (accumulate): pass an empty Hash; after +verify+ returns, read the
      #     keys to see which wtxids the SDK walked. Populates a persistent verification cache.
      #   - **Bidirectional** (both): pass a Hash that seeds the walk AND collects the walked
      #     wtxids in one call.
      #
      #   The Hash is mutated in place — the caller's object identity is preserved.
      #   +nil+ (default) means "no seed, no post-read" — the SDK uses an internal Hash the
      #   caller cannot access. Anything other than +nil+ or +Hash+ raises +ArgumentError+.
      # @return [true] on successful verification
      # @raise [ArgumentError] if +verified:+ is not +nil+ or a +Hash+
      # @raise [VerificationError] with code +:invalid_merkle_proof+ if a merkle proof is invalid
      # @raise [VerificationError] with code +:insufficient_fee+ if the fee is below the model's threshold
      # @raise [VerificationError] with code +:output_overflow+ if outputs exceed inputs
      # @raise [VerificationError] with code +:script_failure+ if script execution fails
      # @raise [VerificationError] with code +:missing_source+ if an input is missing required source data
      # @note Security (trust contract): the caller warrants that every wtxid present in
      #   +verified:+ at method entry is fully verified — script AND chain-anchor (merkle proof)
      #   AND any consensus-flag context. A seeded wtxid is treated as fully verified regardless
      #   of what proof or script data it carries. The SDK does **not** re-run the merkle proof
      #   for a seeded ancestor. If the caller's cache is stale or compromised, +verify+ will
      #   return +true+ for ancestry that has not actually been verified. Cached wtxids are
      #   pinned to the consensus flags under which they were originally verified — invalidate
      #   the caller's cache when consensus flags change, on chain reorganisation, or on any
      #   event that could invalidate a prior verification. Fee validation is not affected by
      #   this set — the fee gate is a caller-passed policy, not a cached claim, and runs once
      #   at the start of every +verify+ call when +fee_model+ is given.
      # @example Pre-seed short-circuit
      #   # wallet has already verified source_tx in a prior session
      #   cache = { source_tx.wtxid => true }
      #   tx.verify(chain_tracker: tracker, verified: cache)
      # @example Post-read accumulate
      #   walked = {}
      #   tx.verify(chain_tracker: tracker, verified: walked)
      #   walked.keys # => [subject_wtxid, ancestor1_wtxid, ...]
      # @example Bidirectional round-trip
      #   cache = load_persistent_verified_cache
      #   tx.verify(chain_tracker: tracker, verified: cache)
      #   save_persistent_verified_cache(cache) # includes newly-walked wtxids
      # @since 0.11.0
      def verify(chain_tracker:, fee_model: nil, verified: nil)
        verified = normalise_verified(verified)
        # Fee gate runs once at the start of every verify call. Fee is a caller-passed policy,
        # not a cached script-validity claim — seeding the subject wtxid cannot silently disable it.
        verify_fee(fee_model) if fee_model

        queue = [self]

        until queue.empty?
          tx = queue.shift
          wtxid = tx.wtxid
          # Top-of-loop dedup covers both walked-during-this-call and caller-seeded wtxids.
          # A seeded wtxid short-circuits everything — including the merkle proof — because
          # the caller warrants full trust. See @note Security.
          next if verified[wtxid]

          if tx.merkle_path
            unless tx.merkle_path.verify(tx.txid_hex, chain_tracker)
              raise VerificationError.new(:invalid_merkle_proof,
                                          "invalid merkle proof for transaction #{tx.txid_hex}")
            end

            verified[wtxid] = true
            next
          end

          # Verify each input
          tx.inputs.each_with_index do |input, index|
            # Populate source data from source_transaction when not already set.
            # Matches the TS SDK pattern: sourceOutput is read directly from
            # source_transaction.outputs[sourceOutputIndex] during verify.
            if input.source_transaction
              source_output = input.source_transaction.outputs[input.prev_tx_out_index]
              if source_output
                input.source_locking_script ||= source_output.locking_script
                input.source_satoshis ||= source_output.satoshis
              end
            end

            verify_input_requirements(tx, input, index)
            begin
              tx.verify_input(index)
            rescue BSV::Script::ScriptError => e
              raise VerificationError.new(
                :script_failure,
                "script verification failed for input #{index} of transaction #{tx.txid_hex}: #{e.message}"
              )
            end

            # Enqueue source transaction unless it's already dealt with (seeded or walked).
            source_tx = input.source_transaction
            queue << source_tx if source_tx && !verified[source_tx.wtxid]
          end

          # Output ≤ input check
          verify_output_constraint(tx)

          verified[wtxid] = true
        end

        true
      end

      # --- Fee estimation ---

      # Sum of all input source satoshi values.
      #
      # @return [Integer] total input value in satoshis
      def total_input_satoshis
        @inputs.each_with_index do |input, idx|
          # F4.4: fall back through source_transaction if source_satoshis is nil.
          if input.source_satoshis.nil? && input.source_transaction
            output = input.source_transaction.outputs[input.prev_tx_out_index]
            input.source_satoshis = output.satoshis if output
          end
          next unless input.source_satoshis.nil?

          raise ArgumentError,
                "input #{idx} has nil source_satoshis — " \
                'set it or wire source_transaction before computing totals'
        end
        @inputs.sum(&:source_satoshis)
      end

      # Sum of all output satoshi values.
      #
      # @return [Integer] total output value in satoshis
      def total_output_satoshis
        @outputs.sum(&:satoshis)
      end

      # Estimate the mining fee based on the estimated transaction size.
      #
      # @deprecated Use {FeeModels::SatoshisPerKilobyte#compute_fee} instead.
      #   This method delegates through +SatoshisPerKilobyte+ internally
      #   and will be removed in 1.0.
      #
      # @param satoshis_per_byte [Numeric] fee rate (default: 0.1 sat/byte = 100 sat/kB,
      #   matching the +SatoshisPerKilobyte+ default)
      # @return [Integer] estimated fee in satoshis (rounded up)
      def estimated_fee(satoshis_per_byte: 0.1)
        unless self.class.instance_variable_get(:@_estimated_fee_warned)
          warn '[DEPRECATION] BSV::Transaction::Tx#estimated_fee is deprecated. ' \
               'Use BSV::Transaction::FeeModels::SatoshisPerKilobyte.new.compute_fee(tx) instead.', uplevel: 1
          self.class.instance_variable_set(:@_estimated_fee_warned, true)
        end
        FeeModels::SatoshisPerKilobyte.new(value: satoshis_per_byte * 1000).compute_fee(self)
      end

      # Estimate the serialised transaction size in bytes.
      #
      # Uses actual unlocking script size for signed inputs and template
      # estimated length for unsigned inputs.
      #
      # @return [Integer] estimated size in bytes
      def estimated_size
        size = 4 # version
        size += VarInt.encode(@inputs.length).bytesize
        @inputs.each_with_index do |input, index|
          size += if input.unlocking_script
                    input.to_binary.bytesize
                  elsif input.unlocking_script_template
                    script_len = input.unlocking_script_template.estimated_length(self, index)
                    32 + 4 + VarInt.encode(script_len).bytesize + script_len + 4
                  else
                    # F4.3: raise instead of silently assuming 148-byte P2PKH.
                    # Matches TS/Go which require either an unlocking script or
                    # a template for size estimation.
                    raise ArgumentError,
                          "input #{index} has no unlocking script or template — " \
                          'cannot estimate size (set unlocking_script_template first)'
                  end
        end
        size += VarInt.encode(@outputs.length).bytesize
        @outputs.each { |o| size += o.to_binary.bytesize }
        size += 4 # lock_time
        size
      end

      # Compute the fee and distribute change across change outputs.
      #
      # Accepts a {FeeModel} instance, a numeric fee in satoshis, or nil
      # (defaults to {FeeModels::SatoshisPerKilobyte} at 50 sat/kB).
      #
      # After computing the fee, distributes remaining satoshis across outputs
      # marked as change. The distribution strategy is controlled by the
      # +change_distribution:+ keyword argument:
      #
      # - +:equal+ (default) — divides change equally across all change outputs,
      #   matching TS SDK default behaviour.
      # - +:random+ — Benford-inspired distribution that biases amounts towards
      #   the lower end of the available range, improving privacy by producing
      #   varied change amounts.
      #
      # If insufficient change remains, all change outputs are removed.
      #
      # @param model_or_fee [FeeModel, Integer, nil] fee model, fixed fee, or nil for default
      # @param change_distribution [Symbol] +:equal+ or +:random+ (default: +:equal+)
      # @return [self] for chaining
      # @raise [ArgumentError] if +change_distribution+ is not +:random+ or +:equal+
      def fee(model_or_fee = nil, change_distribution: :equal)
        unless %i[random equal].include?(change_distribution)
          raise ArgumentError, "invalid change_distribution #{change_distribution.inspect}; expected :random or :equal"
        end

        fee_sats = compute_fee_sats(model_or_fee)
        distribute_change(fee_sats, change_distribution)
        self
      end

      private

      # Resolve the source TransactionOutput for EF serialisation.
      #
      # Returns nil when both explicit fields (+source_satoshis+ and
      # +source_locking_script+) are already set on the input, so no derivation
      # is required. Otherwise, requires a wired +source_transaction+ and a
      # valid output at +prev_tx_out_index+.
      #
      # @param input [Transaction::TransactionInput]
      # @param idx [Integer] input index, used in error messages
      # @return [TransactionOutput, nil]
      def ef_source_output(input, idx)
        return nil if input.source_satoshis && input.source_locking_script

        unless input.source_transaction
          missing = []
          missing << 'source_satoshis' unless input.source_satoshis
          missing << 'source_locking_script' unless input.source_locking_script
          raise ArgumentError,
                "input #{idx} is missing #{missing.join(' and ')} and has no wired source_transaction"
        end

        if input.prev_tx_out_index.nil?
          raise ArgumentError,
                "input #{idx} has no prev_tx_out_index — cannot derive EF source data"
        end

        output = input.source_transaction.outputs[input.prev_tx_out_index]
        return output if output

        raise ArgumentError,
              "input #{idx} source_transaction has no output at index #{input.prev_tx_out_index}"
      end

      # Validate the +verified:+ kwarg for {#verify}.
      #
      # Returns the caller's Hash directly (no dup, no freeze) so the SDK can mutate it in place —
      # the bidirectional contract from {#verify}. When +arg+ is +nil+, returns a fresh empty
      # Hash that the caller has no reference to; that Hash is discarded when +verify+ returns.
      #
      # @param arg [Hash, nil]
      # @return [Hash] the caller's Hash unchanged, or a fresh empty Hash if arg was nil
      # @raise [ArgumentError] if +arg+ is neither +nil+ nor a Hash, or if +arg+ is a frozen Hash
      #   (the SDK writes walked wtxids into it and cannot mutate a frozen Hash)
      def normalise_verified(arg)
        return {} if arg.nil?

        unless arg.is_a?(Hash)
          raise ArgumentError,
                "verified: must be nil or Hash of wtxid => truthy entries (got #{arg.class})"
        end

        if arg.frozen?
          raise ArgumentError,
                'verified: Hash must be mutable — the SDK writes walked wtxids into it'
        end

        arg
      end

      def verify_input_requirements(tx, input, index)
        dtxid_hex = tx.txid_hex
        if input.unlocking_script.nil?
          raise VerificationError.new(:missing_source,
                                      "input #{index} of transaction #{dtxid_hex} has no unlocking script")
        end
        if input.source_locking_script.nil?
          raise VerificationError.new(:missing_source,
                                      "input #{index} of transaction #{dtxid_hex} has no source locking script")
        end
        return unless input.source_satoshis.nil?

        raise VerificationError.new(:missing_source,
                                    "input #{index} of transaction #{dtxid_hex} has no source satoshis")
      end

      def verify_fee(fee_model)
        required_fee = fee_model.compute_fee(self)
        actual_fee = total_input_satoshis - total_output_satoshis
        return if actual_fee >= required_fee

        raise VerificationError.new(:insufficient_fee,
                                    "insufficient fee: transaction pays #{actual_fee} sat but fee model requires #{required_fee} sat")
      end

      def verify_output_constraint(tx)
        input_total = tx.total_input_satoshis
        output_total = tx.total_output_satoshis
        return if output_total <= input_total

        raise VerificationError.new(:output_overflow,
                                    "outputs (#{output_total}) exceed inputs (#{input_total}) for transaction #{tx.txid_hex}")
      end

      ZERO_HASH = ("\x00".b * 32).freeze # rubocop:disable Style/RedundantFreeze
      private_constant :ZERO_HASH

      # @note Memoised; see {file:docs/reference/sighash-cache.md} for the invalidation contract.
      def hash_prevouts(anyone_can_pay)
        return ZERO_HASH if anyone_can_pay

        @hash_prevouts ||=
          BSV::Primitives::Digest.sha256d(@inputs.map(&:outpoint_binary).join).freeze
      end

      # @note Memoised; see {file:docs/reference/sighash-cache.md} for the invalidation contract.
      def hash_sequence(anyone_can_pay, base_type)
        return ZERO_HASH if anyone_can_pay || base_type == Sighash::SINGLE || base_type == Sighash::NONE

        @hash_sequence ||=
          BSV::Primitives::Digest.sha256d(@inputs.map { |i| [i.sequence].pack('V') }.join).freeze
      end

      # @note Memoised; see {file:docs/reference/sighash-cache.md} for the invalidation contract.
      def hash_outputs(base_type, input_index)
        case base_type
        when Sighash::NONE
          ZERO_HASH
        when Sighash::SINGLE
          # NEVER cache the ZERO_HASH branch — after add_output, an idx that was
          # out-of-range may move in-range; a cached ZERO_HASH would be stale.
          return ZERO_HASH if input_index >= @outputs.length

          hash_outputs_single(input_index)
        else # ALL (and any non-standard base type per BIP-143)
          hash_outputs_all
        end
      end

      # Memoises the +hash_outputs+ ALL branch (sha256d of all outputs joined).
      #
      # @!visibility private
      def hash_outputs_all
        @hash_outputs_all ||= BSV::Primitives::Digest.sha256d(@outputs.map(&:to_binary).join).freeze
      end

      # Memoises +hash_outputs+ for the SIGHASH_SINGLE branch, keyed by input
      # index. The Hash itself is the ivar; per-key lookup uses +Hash#[]= ||=+
      # which does not trigger +Naming/MemoizedInstanceVariableName+.
      #
      # @!visibility private
      def hash_outputs_single(input_index)
        @hash_outputs_single ||= {}
        @hash_outputs_single[input_index] ||=
          BSV::Primitives::Digest.sha256d(@outputs[input_index].to_binary).freeze
      end

      # Collect this transaction and all its ancestors in dependency order
      # (ancestors first, self last). Stops recursion at transactions with
      # a merkle_path (proven leaves). Deduplicates by wtxid (wire-order bytes).
      def collect_ancestors
        seen = {}
        result = []
        collect_ancestors_recursive(self, seen, result)
        result
      end

      def collect_ancestors_recursive(tx, seen, result)
        wtxid = tx.wtxid
        return if seen.key?(wtxid)

        if tx.merkle_path
          BSV.logger&.debug do
            "[Tx] ancestor: #{tx.dtxid_hex} proven at height #{tx.merkle_path.block_height} (leaf stop)"
          end
        else
          tx.inputs.each_with_index do |input, idx|
            unless input.source_transaction
              BSV.logger&.debug { "[Tx] ancestor: #{tx.dtxid_hex} input #{idx} has no source_transaction (skipped)" }
              next
            end

            collect_ancestors_recursive(input.source_transaction, seen, result)
          end
        end

        seen[wtxid] = true
        result << tx
      end

      # Group proven ancestors by block height, combine each group into a
      # single compound merkle path (without mutating the source paths), then
      # extract just the txids actually in the bundle. The resulting clean
      # BUMPs are appended to +beef.bumps+, one per block height.
      #
      # @return [Hash{Integer => Integer}] block height → bump index mapping
      def build_beef_bumps(beef, ancestors)
        proven_by_height = ancestors.each_with_object({}) do |tx, h|
          next unless tx.merkle_path

          (h[tx.merkle_path.block_height] ||= []) << tx
        end

        bump_index_by_height = {}
        proven_by_height.each do |height, txs|
          # Deep-dup the first source so combine/trim can't mutate caller state
          merged = txs.first.merkle_path.dup
          txs.drop(1).each { |t| merged.combine(t.merkle_path) }

          wtxid_hashes = txs.map(&:wtxid)
          clean = merged.extract(wtxid_hashes)

          bump_index_by_height[height] = beef.bumps.length
          beef.bumps << clean
        end

        bump_index_by_height
      end

      def compute_fee_sats(model_or_fee)
        case model_or_fee
        when nil
          FeeModels::SatoshisPerKilobyte.new.compute_fee(self)
        when FeeModel
          model_or_fee.compute_fee(self)
        when Numeric
          model_or_fee.ceil # round up — fractional satoshis from callers are not valid; rounding up prevents underpayment
        else
          raise ArgumentError, "expected FeeModel, Numeric, or nil; got #{model_or_fee.class}"
        end
      end

      def distribute_change(fee_sats, change_distribution)
        change_outputs = @outputs.select(&:change)
        return if change_outputs.empty?

        input_sats = total_input_satoshis
        non_change_sats = @outputs.reject(&:change).sum(&:satoshis)
        available = input_sats - non_change_sats - fee_sats

        # F4.1: drop change outputs only when no change is available.
        # Previously compared against change_outputs.length, which dropped
        # outputs even when positive change existed (e.g. 1 sat with 1 output).
        if available <= 0
          @outputs.reject!(&:change)
          return
        end

        if change_distribution == :random
          distribute_random_change(available, change_outputs)
        else
          distribute_equal_change(available, change_outputs)
        end
      end

      def distribute_equal_change(available, change_outputs)
        per_output = available / change_outputs.length
        remainder = available % change_outputs.length
        change_outputs.each_with_index do |output, i|
          output.satoshis = per_output + (i < remainder ? 1 : 0)
        end
      end

      # Distribute change using a Benford-inspired algorithm that biases amounts
      # towards the lower end of the available range.
      #
      # Algorithm:
      # 1. Reserve 1 satoshi per change output as a minimum guarantee.
      # 2. For each output except the last, take a Benford-scaled portion of the
      #    remaining pool and add it to that output's base amount.
      # 3. The last change output receives only its 1 sat base.
      # 4. Any remainder (from floor rounding) is assigned to the last transaction
      #    output, matching TS SDK behaviour.
      #
      # @param available [Integer] total satoshis to distribute
      # @param change_outputs [Array<TransactionOutput>] outputs flagged as change
      # @return [void]
      def distribute_random_change(available, change_outputs)
        n = change_outputs.length

        # Initialise each output with a 1-sat base and reserve that pool
        amounts = Array.new(n, 1)
        pool = available - n
        distributed = n

        # Allocate Benford-scaled portions to all outputs except the last
        (n - 1).times do |i|
          portion = benford_number(0, pool)
          amounts[i] += portion
          distributed += portion
          pool -= portion
        end

        # Assign computed amounts to change outputs
        change_outputs.each_with_index do |output, i|
          output.satoshis = amounts[i]
        end

        # Assign any remainder (floor-rounding loss) to the last transaction output
        remainder = available - distributed
        return unless remainder.positive?

        last_output = @outputs.last
        last_output.satoshis = (last_output.satoshis || 0) + remainder
      end

      # Generate a Benford-inspired integer in the range [min, max).
      #
      # Randomly selects a scale factor that biases the result towards the lower end of
      # the range, based on the Benford distribution of leading digits.
      #
      # Reference ts SDK implementation
      # Math.floor(min + ((max - min) * Math.log10(1 + 1 / d)) / Math.log10(10))
      #
      # We simplify:
      #  - log10(10) = 1, divide by 1 is a no-op, removed it
      #  - pre-calculated the 9 possible values to a look-up table LOG10_RECIPROCAL_D_VALUES_1TO9
      #  - rearrange to "start at min, add a scaled portion of the range"
      #
      # @param min [Integer] lower bound (inclusive)
      # @param max [Integer] upper bound (exclusive)
      # @return [Integer] Benford-distributed integer
      def benford_number(min, max)
        scale_factor = LOG10_RECIPROCAL_D_VALUES_1TO9[Random.rand(9)] # Array indexing starts at 0
        (min + (scale_factor * (max - min))).floor
      end

      # Clears the +hash_sequence+ component-hash memo. Called by
      # +TransactionInput#sequence=+ via the owning-Tx backref.
      #
      # @!visibility private
      def invalidate_sequence_components_cache
        @hash_sequence = nil
      end

      # Clears the +hash_outputs+ component-hash memos (both the ALL branch and
      # the SIGHASH_SINGLE per-index cache). Called by
      # +TransactionOutput#satoshis=+ and +TransactionOutput#locking_script=+
      # via the owning-Tx backref.
      #
      # @!visibility private
      def invalidate_outputs_components_cache
        @hash_outputs_all = nil
        @hash_outputs_single&.clear
      end

      # Clears the L2 wire-serialisation caches (+to_binary+ and +wtxid+).
      # Called by per-struct setter bubbles and +invalidate_caches+.
      #
      # @!visibility private
      def invalidate_wire_cache
        @to_binary = nil
        @wtxid = nil
      end

      # Clears every cache slice on this Tx without the +rebind_owning_tx!+
      # walk. Called from +add_input+ / +add_output+ where the new struct's
      # backref was just set inline and existing structs' backrefs were
      # established when they were added — making the rebind walk redundant
      # and reducing N-input construction from O(N²) to O(N).
      #
      # The public +invalidate_caches+ keeps the rebind walk because it is
      # the documented escape hatch for direct array mutation, where the
      # walk is required.
      #
      # @!visibility private
      def clear_caches
        @hash_prevouts = nil
        invalidate_sequence_components_cache
        invalidate_outputs_components_cache
        invalidate_wire_cache
      end

      # Restore +@owning_tx+ on every current input and output. Called by
      # +invalidate_caches+ so the escape hatch covers direct array mutation
      # (e.g. +tx.inputs << input+ bypasses +add_input+ and leaves the new
      # struct's backref nil — subsequent setter mutations would not bubble
      # invalidation).
      #
      # Raises if any struct is currently attached to a *different* Tx —
      # matches the +add_input+ / +add_output+ cross-Tx rebind contract.
      #
      # @!visibility private
      def rebind_owning_tx!
        (@inputs + @outputs).each do |struct|
          existing_owner = struct.instance_variable_get(:@owning_tx)
          if existing_owner && !existing_owner.equal?(self)
            raise ArgumentError,
                  "#{struct.class.name.split('::').last} is already attached to a different Tx; " \
                  'invalidate_caches cannot rebind across transactions'
          end

          struct.instance_variable_set(:@owning_tx, self)
        end
      end
    end
  end
end
