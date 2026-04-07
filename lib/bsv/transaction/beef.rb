# frozen_string_literal: true

require 'set'

module BSV
  module Transaction
    # Background Evaluation Extended Format (BEEF) for SPV-ready transaction
    # bundles. Encodes one or more transactions together with their merkle
    # proofs (BUMPs), enabling recipients to verify inclusion without
    # querying a block explorer.
    #
    # Supports BRC-62 (V1), BRC-96 (V2), and BRC-95 (Atomic BEEF) formats.
    #
    # @example Parse a BEEF bundle and find a transaction
    #   beef = BSV::Transaction::Beef.from_hex(beef_hex)
    #   tx = beef.find_transaction(txid_bytes)
    class Beef
      # @!group Version constants

      # Version magic bytes as LE uint32 (matching pack('V') / unpack1('V')).
      # Stream bytes: 01 00 BE EF / 02 00 BE EF / 01 01 01 01
      BEEF_V1     = 0xEFBE0001 # BRC-62
      BEEF_V2     = 0xEFBE0002 # BRC-96
      ATOMIC_BEEF = 0x01010101 # BRC-95

      # @!endgroup

      # @!group Transaction format flags

      # Raw transaction without a merkle proof.
      FORMAT_RAW_TX             = 0
      # Raw transaction with an associated BUMP index.
      FORMAT_RAW_TX_AND_BUMP    = 1
      # Only the transaction ID (no raw data).
      FORMAT_TXID_ONLY          = 2

      # @!endgroup

      # A single entry in a BEEF bundle, wrapping a transaction with its format metadata.
      class BeefTx
        # @return [Integer] format flag (FORMAT_RAW_TX, FORMAT_RAW_TX_AND_BUMP, or FORMAT_TXID_ONLY)
        attr_reader :format

        # @return [Transaction, nil] the transaction (nil for TXID-only entries)
        attr_reader :transaction

        # @return [String, nil] 32-byte txid for TXID-only entries
        attr_reader :known_txid

        # @return [Integer, nil] index into the BEEF bumps array
        attr_reader :bump_index

        # @param format [Integer] format flag
        # @param transaction [Transaction, nil] the transaction
        # @param known_txid [String, nil] 32-byte txid for TXID-only entries
        # @param bump_index [Integer, nil] index into the bumps array
        # @raise [ArgumentError] if format is FORMAT_RAW_TX_AND_BUMP without a bump_index
        def initialize(format:, transaction: nil, known_txid: nil, bump_index: nil)
          raise ArgumentError, 'FORMAT_RAW_TX_AND_BUMP requires a bump_index' if format == FORMAT_RAW_TX_AND_BUMP && bump_index.nil?

          @format = format
          @transaction = transaction
          @known_txid = known_txid
          @bump_index = bump_index
        end

        # The transaction ID for this entry.
        #
        # @return [String, nil] 32-byte txid in display byte order
        def txid
          case @format
          when FORMAT_TXID_ONLY
            @known_txid
          else
            @transaction&.txid
          end
        end
      end

      # @return [Integer] BEEF version constant
      attr_reader :version

      # @return [Array<MerklePath>] merkle proofs (BUMPs) referenced by transactions
      attr_reader :bumps

      # @return [Array<BeefTx>] the transactions in dependency order
      attr_reader :transactions

      # @return [String, nil] 32-byte subject txid (Atomic BEEF only)
      attr_reader :subject_txid

      # @param version [Integer] BEEF version constant (default: BEEF_V2)
      # @param bumps [Array<MerklePath>] merkle proofs
      # @param transactions [Array<BeefTx>] transaction entries
      def initialize(version: BEEF_V2, bumps: [], transactions: [])
        @version = version
        @bumps = bumps
        @transactions = transactions
        @subject_txid = nil
      end

      # --- Deserialisation ---

      # Deserialise a BEEF bundle from binary data.
      #
      # Supports V1 (BRC-62), V2 (BRC-96), and Atomic (BRC-95) formats.
      # After parsing, input source transactions are wired automatically.
      #
      # @param data [String] raw BEEF binary
      # @return [Beef] the parsed BEEF bundle
      def self.from_binary(data)
        raise ArgumentError, "truncated BEEF: need at least 4 bytes for version, got #{data.bytesize}" if data.bytesize < 4

        offset = 0

        version = data.byteslice(offset, 4).unpack1('V')
        offset += 4

        beef = new(version: version)

        if version == ATOMIC_BEEF
          if data.bytesize < offset + 36
            remaining = data.bytesize - offset
            raise ArgumentError, "truncated Atomic BEEF: need 36 bytes at offset #{offset}, got #{remaining}"
          end

          # Atomic BEEF stores the subject txid in internal byte order (little-endian
          # hash order), matching JS and Go SDKs. Reverse to display order for internal use.
          beef.instance_variable_set(:@subject_txid, data.byteslice(offset, 32).reverse)
          offset += 32
          inner_version = data.byteslice(offset, 4).unpack1('V')
          offset += 4
          beef.instance_variable_set(:@version, inner_version)
        end

        offset = read_bumps(beef, data, offset)

        case version == ATOMIC_BEEF ? beef.version : version
        when BEEF_V2
          read_v2_transactions(beef, data, offset)
        when BEEF_V1
          read_v1_transactions(beef, data, offset)
        end

        wire_source_transactions(beef)

        beef
      end

      # Deserialise a BEEF bundle from a hex string.
      #
      # @param hex [String] hex-encoded BEEF data
      # @return [Beef] the parsed BEEF bundle
      def self.from_hex(hex)
        from_binary([hex].pack('H*'))
      end

      # --- Serialisation ---

      # Serialise the BEEF bundle to binary format.
      #
      # Defaults to V1 (BRC-62) for compatibility with ARC and the
      # reference TS SDK. Pass +version: BEEF_V2+ for BRC-96 format.
      #
      # @param version [Integer] BEEF_V1 (default) or BEEF_V2
      # @return [String] raw BEEF binary
      def to_binary(version: BEEF_V1)
        buf = [version].pack('V')

        buf << VarInt.encode(@bumps.length)
        @bumps.each { |bump| buf << bump.to_binary }

        buf << VarInt.encode(@transactions.length)
        @transactions.each do |beef_tx|
          if version == BEEF_V2
            write_v2_tx(buf, beef_tx)
          else
            write_v1_tx(buf, beef_tx)
          end
        end

        buf
      end

      # Serialise the BEEF bundle to a V2 hex string.
      #
      # @return [String] hex-encoded BEEF data
      def to_hex
        to_binary.unpack1('H*')
      end

      # Serialise as Atomic BEEF (BRC-95), wrapping V2 data with a subject txid.
      #
      # @param subject_txid [String] 32-byte subject transaction ID
      # @return [String] raw Atomic BEEF binary
      def to_atomic_binary(subject_txid)
        buf = [ATOMIC_BEEF].pack('V')
        # Write subject txid in internal byte order (reverse of display order),
        # matching JS and Go SDK conventions for Bitcoin binary formats.
        buf << subject_txid.b.reverse
        # BRC-95: inner envelope is always V2
        buf << to_binary(version: BEEF_V2)
        buf
      end

      # --- Lookup ---

      # Find a transaction in the bundle by its transaction ID.
      #
      # @param txid [String] 32-byte txid in display byte order
      # @return [Transaction, nil] the matching transaction, or nil
      def find_transaction(txid)
        @transactions.each do |beef_tx|
          return beef_tx.transaction if beef_tx.transaction&.txid == txid
        end
        nil
      end

      # Find the merkle path (BUMP) for a transaction by its txid.
      #
      # @param txid [String] 32-byte txid in display byte order
      # @return [MerklePath, nil] the merkle path, or nil if not found
      def find_bump(txid)
        bt = @transactions.find { |entry| entry.txid == txid && entry.format == FORMAT_RAW_TX_AND_BUMP }
        return unless bt

        bt.transaction&.merkle_path || (bt.bump_index && @bumps[bt.bump_index])
      end

      # Find a transaction with all source_transactions wired for signing.
      #
      # @param txid [String] 32-byte txid in display byte order
      # @return [Transaction, nil] the transaction with wired inputs, or nil
      def find_transaction_for_signing(txid)
        tx = find_transaction(txid)
        return unless tx

        wire_inputs(tx)
        tx
      end

      # Find a transaction and recursively wire its ancestry (source transactions
      # and merkle paths) for atomic proof validation.
      #
      # @param txid [String] 32-byte txid in display byte order
      # @return [Transaction, nil] the transaction with full proof tree, or nil
      def find_atomic_transaction(txid)
        tx = find_transaction(txid)
        return unless tx

        wire_ancestry(tx)
        tx
      end

      # Serialise as Atomic BEEF (BRC-95) hex string.
      #
      # @param subject_txid [String] 32-byte subject transaction ID
      # @return [String] hex-encoded Atomic BEEF
      def to_atomic_hex(subject_txid)
        to_atomic_binary(subject_txid).unpack1('H*')
      end

      # --- Merge operations ---

      # Add or deduplicate a merkle path (BUMP) in this BEEF bundle.
      #
      # If an existing BUMP shares the same block_height and merkle root,
      # it is combined (via MerklePath#combine) and the existing index is
      # returned. Otherwise the BUMP is appended.
      #
      # @param merkle_path [MerklePath] the BUMP to merge
      # @return [Integer] the index of the (possibly merged) BUMP
      def merge_bump(merkle_path)
        root = merkle_path.compute_root
        @bumps.each_with_index do |existing, idx|
          next unless existing.block_height == merkle_path.block_height

          if existing.compute_root == root
            existing.combine(merkle_path)
            return idx
          end
        end

        @bumps << merkle_path
        @bumps.length - 1
      end

      # Add a transaction to this BEEF bundle.
      #
      # Recursively merges the transaction's ancestors (via source_transaction
      # references on inputs) and their merkle paths. Duplicate transactions
      # (same txid) are not re-added.
      #
      # @param tx [Transaction] the transaction to merge
      # @return [BeefTx] the (possibly existing) BeefTx entry
      def merge_transaction(tx)
        txid = tx.txid

        # Check for existing entry
        existing = @transactions.find { |bt| bt.txid == txid }
        return existing if existing

        # Recursively merge ancestors first (dependency order)
        tx.inputs.each do |input|
          merge_transaction(input.source_transaction) if input.source_transaction
        end

        # Merge this transaction's BUMP if it has one
        entry = if tx.merkle_path
                  bump_idx = merge_bump(tx.merkle_path)
                  BeefTx.new(format: FORMAT_RAW_TX_AND_BUMP, transaction: tx, bump_index: bump_idx)
                else
                  BeefTx.new(format: FORMAT_RAW_TX, transaction: tx)
                end
        @transactions << entry
        entry
      end

      # Add a transaction from raw binary data.
      #
      # @param raw_bytes [String] raw transaction binary
      # @param bump_index [Integer, nil] optional BUMP index
      # @return [BeefTx] the new BeefTx entry
      def merge_raw_tx(raw_bytes, bump_index: nil)
        tx = Transaction.from_binary(raw_bytes)
        existing = @transactions.find { |bt| bt.txid == tx.txid }
        return existing if existing

        entry = if bump_index
                  unless bump_index.is_a?(Integer) && bump_index >= 0 && bump_index < @bumps.length
                    raise ArgumentError,
                          "bump_index #{bump_index.inspect} out of range (have #{@bumps.length} bumps)"
                  end

                  tx.merkle_path = @bumps[bump_index]
                  BeefTx.new(format: FORMAT_RAW_TX_AND_BUMP, transaction: tx, bump_index: bump_index)
                else
                  BeefTx.new(format: FORMAT_RAW_TX, transaction: tx)
                end
        @transactions << entry
        entry
      end

      # Merge all BUMPs and transactions from another BEEF bundle.
      #
      # BUMP indices are remapped during merge.
      #
      # @param other [Beef] the BEEF bundle to merge from
      # @return [self]
      def merge(other)
        # Build index remap for BUMPs
        bump_remap = {}
        other.bumps.each_with_index do |bump, old_idx|
          bump_remap[old_idx] = merge_bump(bump)
        end

        # Merge transactions with remapped BUMP indices
        other.transactions.each do |beef_tx|
          case beef_tx.format
          when FORMAT_TXID_ONLY
            next if @transactions.any? { |bt| bt.txid == beef_tx.known_txid }

            @transactions << BeefTx.new(format: FORMAT_TXID_ONLY, known_txid: beef_tx.known_txid)
          else
            next if @transactions.any? { |bt| bt.txid == beef_tx.txid }

            if beef_tx.format == FORMAT_RAW_TX_AND_BUMP && beef_tx.bump_index
              new_idx = bump_remap[beef_tx.bump_index] || beef_tx.bump_index
              beef_tx.transaction.merkle_path = @bumps[new_idx]
              @transactions << BeefTx.new(
                format: FORMAT_RAW_TX_AND_BUMP,
                transaction: beef_tx.transaction,
                bump_index: new_idx
              )
            else
              @transactions << BeefTx.new(format: FORMAT_RAW_TX, transaction: beef_tx.transaction)
            end
          end
        end

        self
      end

      # Convert a transaction entry to TXID-only format.
      #
      # @param txid [String] 32-byte txid in display byte order
      # @return [BeefTx, nil] the converted entry, or nil if not found
      def make_txid_only(txid)
        idx = @transactions.index { |bt| bt.txid == txid }
        return unless idx

        @transactions[idx] = BeefTx.new(format: FORMAT_TXID_ONLY, known_txid: txid)
      end

      # --- Validation ---

      # Check structural validity of the BEEF bundle.
      #
      # A valid BEEF has every transaction either:
      # - proven (has a BUMP / merkle_path), or
      # - all its inputs reference transactions that are themselves valid
      #   within this bundle.
      #
      # @param allow_txid_only [Boolean] whether TXID-only entries count as valid (default: false)
      # @return [Boolean] true if structurally valid
      def valid?(allow_txid_only: false)
        known_txids = build_known_txids(allow_txid_only)

        # TXID-only entries are invalid unless explicitly allowed
        has_txid_only = @transactions.any? { |bt| bt.format == FORMAT_TXID_ONLY }
        return false if has_txid_only && !allow_txid_only

        pending = @transactions.select { |bt| bt.transaction && !known_txids.include?(bt.txid) }

        # Iteratively resolve: if all inputs of a tx are known, it becomes known
        changed = true
        while changed
          changed = false
          pending.reject! do |bt|
            all_inputs_known = bt.transaction.inputs.all? do |input|
              known_txids.include?(input.prev_tx_id.reverse)
            end
            if all_inputs_known
              known_txids.add(bt.txid)
              changed = true
            end
            all_inputs_known
          end
        end

        pending.empty?
      end

      # Sort transactions in topological (dependency) order in place.
      #
      # After sorting, every transaction's input ancestors appear before it
      # in the array. This is required for correct BEEF serialisation.
      #
      # @return [self]
      def sort_transactions!
        return self if @transactions.length <= 1

        txid_index = {}
        @transactions.each_with_index { |bt, i| txid_index[bt.txid] = i }

        # Build adjacency: for each tx, which other txs must come before it?
        in_degree = Array.new(@transactions.length, 0)
        dependents = Array.new(@transactions.length) { [] }

        @transactions.each_with_index do |bt, i|
          next unless bt.transaction

          bt.transaction.inputs.each do |input|
            dep_idx = txid_index[input.prev_tx_id.reverse]
            next unless dep_idx

            dependents[dep_idx] << i
            in_degree[i] += 1
          end
        end

        # Kahn's algorithm
        queue = (0...@transactions.length).select { |i| in_degree[i].zero? }
        sorted = []

        until queue.empty?
          idx = queue.shift
          sorted << @transactions[idx]
          dependents[idx].each do |dep|
            in_degree[dep] -= 1
            queue << dep if in_degree[dep].zero?
          end
        end

        @transactions = sorted
        self
      end

      # --- Private class methods for deserialisation ---

      class << self
        private

        def read_bumps(beef, data, offset)
          num_bumps, vi_size = VarInt.decode(data, offset)
          offset += vi_size

          num_bumps.times do
            mp, consumed = MerklePath.from_binary(data, offset)
            beef.bumps << mp
            offset += consumed
          end

          offset
        end

        def read_v2_transactions(beef, data, offset)
          num_txs, vi_size = VarInt.decode(data, offset)
          offset += vi_size

          num_txs.times do
            format = data.getbyte(offset)
            offset += 1

            case format
            when FORMAT_TXID_ONLY
              known_txid = data.byteslice(offset, 32)
              offset += 32
              beef.transactions << BeefTx.new(format: FORMAT_TXID_ONLY, known_txid: known_txid)
            when FORMAT_RAW_TX_AND_BUMP
              bump_index, vi_size = VarInt.decode(data, offset)
              offset += vi_size
              tx, consumed = Transaction.from_binary_with_offset(data, offset)
              offset += consumed
              tx.merkle_path = beef.bumps[bump_index] if bump_index < beef.bumps.length
              beef.transactions << BeefTx.new(
                format: FORMAT_RAW_TX_AND_BUMP, transaction: tx, bump_index: bump_index
              )
            when FORMAT_RAW_TX
              tx, consumed = Transaction.from_binary_with_offset(data, offset)
              offset += consumed
              beef.transactions << BeefTx.new(format: FORMAT_RAW_TX, transaction: tx)
            end
          end

          offset
        end

        def read_v1_transactions(beef, data, offset)
          num_txs, vi_size = VarInt.decode(data, offset)
          offset += vi_size

          num_txs.times do
            tx, consumed = Transaction.from_binary_with_offset(data, offset)
            offset += consumed

            has_bump = data.getbyte(offset)
            offset += 1

            if has_bump.zero?
              beef.transactions << BeefTx.new(format: FORMAT_RAW_TX, transaction: tx)
            else
              bump_index, vi_size = VarInt.decode(data, offset)
              offset += vi_size
              tx.merkle_path = beef.bumps[bump_index] if bump_index < beef.bumps.length
              beef.transactions << BeefTx.new(
                format: FORMAT_RAW_TX_AND_BUMP, transaction: tx, bump_index: bump_index
              )
            end
          end

          offset
        end

        def wire_source_transactions(beef)
          tx_map = {}
          beef.transactions.each do |beef_tx|
            next unless beef_tx.transaction

            # Wire inputs to ancestors already in the map (BEEF is dependency-ordered)
            beef_tx.transaction.inputs.each do |input|
              # prev_tx_id is wire byte order; txid keys are display byte order (reversed)
              source = tx_map[input.prev_tx_id.reverse]
              input.source_transaction = source if source
            end

            tx_map[beef_tx.transaction.txid] = beef_tx.transaction
          end
        end
      end

      private

      # Build a set of txids that are "known" (proven or txid-only).
      def build_known_txids(allow_txid_only)
        known = Set.new
        @transactions.each do |bt|
          case bt.format
          when FORMAT_RAW_TX_AND_BUMP
            known.add(bt.txid)
          when FORMAT_TXID_ONLY
            known.add(bt.txid) if allow_txid_only
          end
        end
        known
      end

      # Wire source_transaction references on a transaction's inputs.
      def wire_inputs(tx)
        tx.inputs.each do |input|
          next if input.source_transaction

          source = find_transaction(input.prev_tx_id.reverse)
          input.source_transaction = source if source
        end
      end

      # Recursively wire source_transactions and merkle_paths.
      def wire_ancestry(tx)
        wire_inputs(tx)
        tx.inputs.each do |input|
          next unless input.source_transaction

          source = input.source_transaction
          source.merkle_path ||= find_bump(source.txid)
          wire_ancestry(source)
        end
      end

      # V1 (BRC-62): raw_tx + has_bump(byte) [+ bump_index(varint)]
      def write_v1_tx(buf, beef_tx)
        buf << beef_tx.transaction.to_binary
        if beef_tx.format == FORMAT_RAW_TX_AND_BUMP
          buf << [1].pack('C')
          buf << VarInt.encode(beef_tx.bump_index)
        else
          buf << [0].pack('C')
        end
      end

      # V2 (BRC-96): format_byte [+ bump_index(varint)] + raw_tx
      def write_v2_tx(buf, beef_tx)
        case beef_tx.format
        when FORMAT_TXID_ONLY
          buf << [FORMAT_TXID_ONLY].pack('C')
          buf << beef_tx.known_txid
        when FORMAT_RAW_TX_AND_BUMP
          buf << [FORMAT_RAW_TX_AND_BUMP].pack('C')
          buf << VarInt.encode(beef_tx.bump_index)
          buf << beef_tx.transaction.to_binary
        else
          buf << [FORMAT_RAW_TX].pack('C')
          buf << beef_tx.transaction.to_binary
        end
      end
    end
  end
end
