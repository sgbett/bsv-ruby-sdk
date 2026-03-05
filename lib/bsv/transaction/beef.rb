# frozen_string_literal: true

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
        def initialize(format:, transaction: nil, known_txid: nil, bump_index: nil)
          @format = format
          @transaction = transaction
          @known_txid = known_txid
          @bump_index = bump_index
        end

        # The transaction ID for this entry.
        #
        # @return [String, nil] 32-byte txid in internal byte order
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
          raise ArgumentError, "truncated Atomic BEEF: need 36 bytes for subject txid + inner version at offset #{offset}, got #{data.bytesize - offset}" if data.bytesize < offset + 36

          beef.instance_variable_set(:@subject_txid, data.byteslice(offset, 32))
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

      # --- Serialisation (always V2) ---

      # Serialise the BEEF bundle to V2 (BRC-96) binary format.
      #
      # @return [String] raw BEEF binary
      def to_binary
        bump_map = build_bump_map
        bumps_to_write = bump_map.values.sort_by { |entry| entry[:index] }.map { |entry| entry[:bump] }

        buf = [BEEF_V2].pack('V')

        buf << VarInt.encode(bumps_to_write.length)
        bumps_to_write.each { |bump| buf << bump.to_binary }

        buf << VarInt.encode(@transactions.length)
        @transactions.each do |beef_tx|
          case beef_tx.format
          when FORMAT_TXID_ONLY
            buf << [FORMAT_TXID_ONLY].pack('C')
            buf << beef_tx.known_txid
          when FORMAT_RAW_TX_AND_BUMP
            buf << [FORMAT_RAW_TX_AND_BUMP].pack('C')
            mp = beef_tx.transaction.merkle_path
            idx = bump_map[mp][:index]
            buf << VarInt.encode(idx)
            buf << beef_tx.transaction.to_binary
          else
            buf << [FORMAT_RAW_TX].pack('C')
            buf << beef_tx.transaction.to_binary
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
        buf << subject_txid
        buf << to_binary
        buf
      end

      # --- Lookup ---

      # Find a transaction in the bundle by its transaction ID.
      #
      # @param txid [String] 32-byte txid in internal byte order
      # @return [Transaction, nil] the matching transaction, or nil
      def find_transaction(txid)
        @transactions.each do |beef_tx|
          return beef_tx.transaction if beef_tx.transaction&.txid == txid
        end
        nil
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
              # prev_tx_id is internal byte order; txid keys are display order (reversed)
              source = tx_map[input.prev_tx_id.reverse]
              input.source_transaction = source if source
            end

            tx_map[beef_tx.transaction.txid] = beef_tx.transaction
          end
        end
      end

      private

      def build_bump_map
        map = {}.compare_by_identity
        idx = 0
        @transactions.each do |beef_tx|
          next unless beef_tx.format == FORMAT_RAW_TX_AND_BUMP
          next unless beef_tx.transaction&.merkle_path

          mp = beef_tx.transaction.merkle_path
          unless map.key?(mp)
            map[mp] = { bump: mp, index: idx }
            idx += 1
          end
        end
        map
      end
    end
  end
end
