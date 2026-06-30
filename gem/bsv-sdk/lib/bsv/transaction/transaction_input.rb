# frozen_string_literal: true

module BSV
  module Transaction
    # A transaction input referencing a previous output to spend.
    #
    # Inputs identify the output being spent by its transaction ID and
    # output index (the "outpoint"), and provide an unlocking script to
    # satisfy the locking script conditions.
    class TransactionInput
      # @return [String] 32-byte wire-order transaction ID of the output being spent
      attr_reader :prev_wtxid

      # @return [Integer] index of the output within the previous transaction
      attr_reader :prev_tx_out_index

      # @!attribute [rw] sequence
      #   @return [Integer] sequence number (default: 0xFFFFFFFF)
      #   @note Setting this invalidates the owning Tx's wire cache and the
      #     hash_sequence component of the sighash cache. See
      #     {file:docs/reference/sighash-cache.md}.
      attr_reader :sequence

      # @!attribute [rw] unlocking_script
      #   @return [Script::Script, nil] the unlocking script (set after signing)
      #   @note Setting this invalidates the owning Tx's wire cache only.
      #     The unlocking script does not enter the BIP-143 preimage, so the
      #     sighash component caches are not touched. See
      #     {file:docs/reference/sighash-cache.md}.
      attr_reader :unlocking_script

      # @return [Integer, nil] satoshi value of the source output (needed for sighash)
      # @note Enters the BIP-143 preimage at step 6 but no current cache layer
      #   memoises the per-input preimage, so no invalidator is required. If a
      #   future change adds preimage or per-input digest memoisation, add a
      #   setter override here that invalidates the relevant cache slice. See
      #   {file:docs/reference/sighash-cache.md}.
      attr_accessor :source_satoshis

      # @return [Script::Script, nil] locking script of the source output (needed for sighash)
      # @note Enters the BIP-143 preimage as scriptCode (step 5) when no
      #   subscript override is supplied. Same caveat as {#source_satoshis}:
      #   no current cache layer depends on this field, but a future preimage
      #   cache would need a setter override here. See
      #   {file:docs/reference/sighash-cache.md}.
      attr_accessor :source_locking_script

      # @return [Transaction::Tx, nil] the full source transaction (for BEEF wiring)
      # @note Source data is lazily resolved from this Tx during {Tx#verify}
      #   and {Tx#sighash_preimage}. Mutation of this field after resolution
      #   has occurred has no effect on caches because no current cache layer
      #   depends on resolved source data.
      attr_accessor :source_transaction

      # @return [UnlockingScriptTemplate, nil] template for deferred signing
      attr_accessor :unlocking_script_template

      # @param prev_wtxid [String] 32-byte wire-order transaction ID
      # @param prev_tx_out_index [Integer] output index in the previous transaction
      # @param unlocking_script [Script::Script, nil] unlocking script (nil if unsigned)
      # @param sequence [Integer] sequence number
      def initialize(prev_wtxid:, prev_tx_out_index:, unlocking_script: nil, sequence: 0xFFFFFFFF)
        BSV::Primitives::Hex.validate_wtxid!(prev_wtxid, name: 'prev_wtxid')
        @prev_wtxid = prev_wtxid.b
        @prev_tx_out_index = prev_tx_out_index
        @unlocking_script = unlocking_script
        @sequence = sequence
        @owning_tx = nil
        BSV.logger&.debug { "[TransactionInput] prev_wtxid set: #{dtxid_hex}:#{@prev_tx_out_index}" }
      end

      # Called by +#dup+ and +#clone+. Clears the owning-Tx backref so that the
      # cloned input does not belong to any transaction until it is explicitly
      # added via +Tx#add_input+.
      def initialize_copy(other)
        super
        @owning_tx = nil
      end

      # Sets the sequence number and invalidates the L1 binary memo and any
      # owning-Tx slice caches that incorporate sequence (BIP-143 preimage
      # and wire format).
      #
      # @param value [Integer] new sequence number
      def sequence=(value)
        @sequence = value
        @to_binary = nil
        @owning_tx&.send(:invalidate_sequence_components_cache)
        @owning_tx&.send(:invalidate_wire_cache)
      end

      # Sets the unlocking script and invalidates the L1 binary memo and the
      # owning-Tx wire cache. Unlocking script does not enter the BIP-143
      # preimage, so the sequence/outputs components caches are not touched.
      #
      # @param value [Script::Script, nil] new unlocking script
      def unlocking_script=(value)
        @unlocking_script = value
        @to_binary = nil
        @owning_tx&.send(:invalidate_wire_cache)
      end

      # Serialise the input to its binary wire format.
      #
      # @note Memoised; see {file:docs/reference/sighash-cache.md} for the invalidation contract.
      # @return [String] binary input (outpoint + varint + script + sequence)
      def to_binary
        @to_binary ||= begin
          script_bytes = @unlocking_script ? @unlocking_script.to_binary : ''.b
          (@prev_wtxid +
            [@prev_tx_out_index].pack('V') +
            VarInt.encode(script_bytes.bytesize) +
            script_bytes +
            [@sequence].pack('V')).freeze
        end
      end

      # Deserialise a transaction input from binary data.
      #
      # @param data [String] binary data
      # @param offset [Integer] byte offset to start reading from
      # @return [Array(TransactionInput, Integer)] the input and bytes consumed
      def self.from_binary(data, offset = 0)
        if data.bytesize < offset + 36
          raise ArgumentError,
                "truncated input: need 36 bytes for outpoint at offset #{offset}, got #{data.bytesize - offset}"
        end

        prev_wtxid = data.byteslice(offset, 32)
        prev_tx_out_index = data.byteslice(offset + 32, 4).unpack1('V')
        offset += 36

        script_len, vi_size = VarInt.decode(data, offset)
        offset += vi_size

        if data.bytesize < offset + script_len
          raise ArgumentError,
                "truncated input: need #{script_len} bytes for script at offset #{offset}, got #{data.bytesize - offset}"
        end

        unlocking_script = (BSV::Script::Script.from_binary(data.byteslice(offset, script_len)) if script_len.positive?)
        offset += script_len

        if data.bytesize < offset + 4
          raise ArgumentError,
                "truncated input: need 4 bytes for sequence at offset #{offset}, got #{data.bytesize - offset}"
        end

        sequence = data.byteslice(offset, 4).unpack1('V')

        total = 36 + vi_size + script_len + 4
        input = new(
          prev_wtxid: prev_wtxid,
          prev_tx_out_index: prev_tx_out_index,
          unlocking_script: unlocking_script,
          sequence: sequence
        )
        [input, total]
      end

      # Convert a display-order hex transaction ID to wire-order bytes.
      #
      # @param hex [String] hex-encoded transaction ID (display order)
      # @return [String] 32-byte transaction ID in wire byte order
      def self.wtxid_from_hex(hex)
        BSV::Primitives::Hex.validate_dtxid_hex!(hex, name: 'wtxid_from_hex input')
        wtxid = [hex].pack('H*').reverse
        BSV.logger&.debug { "[TransactionInput] wtxid_from_hex: #{hex} -> #{wtxid.bytesize}B wire-order" }
        wtxid
      end

      # Serialise the outpoint (prev_wtxid + output index) as binary.
      #
      # Memoised: outpoint components are +attr_reader+ only so the value is
      # immutable after construction. Returns a frozen binary string.
      #
      # @note Memoised; see {file:docs/reference/sighash-cache.md} for the invalidation contract.
      # @return [String] 36-byte outpoint
      def outpoint_binary
        @outpoint_binary ||= (@prev_wtxid + [@prev_tx_out_index].pack('V')).freeze
      end

      # The previous transaction ID in display-order hex.
      #
      # @return [String] hex-encoded transaction ID (display order)
      def dtxid_hex
        @prev_wtxid.reverse.unpack1('H*')
      end
    end
  end
end
