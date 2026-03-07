# frozen_string_literal: true

module BSV
  module Transaction
    # A BRC-74 merkle path (BUMP — Bitcoin Unified Merkle Path).
    #
    # Encodes the proof that a transaction is included in a block by
    # storing the minimum set of intermediate hashes needed to recompute
    # the block's merkle root from a given transaction ID.
    #
    # @example Parse a BUMP from hex and compute the merkle root
    #   mp = BSV::Transaction::MerklePath.from_hex(bump_hex)
    #   root_hex = mp.compute_root_hex(txid_hex)
    class MerklePath
      # A single leaf in one level of the merkle path.
      #
      # @!attribute [r] offset
      #   @return [Integer] position index within the tree level
      # @!attribute [r] hash
      #   @return [String, nil] 32-byte hash (nil when duplicate)
      # @!attribute [r] txid
      #   @return [Boolean] whether this leaf is a transaction ID
      # @!attribute [r] duplicate
      #   @return [Boolean] whether this leaf duplicates its sibling
      class PathElement
        attr_reader :offset, :hash, :txid, :duplicate

        # @param offset [Integer] position index within the tree level
        # @param hash [String, nil] 32-byte hash (nil when duplicate)
        # @param txid [Boolean] whether this leaf is a transaction ID
        # @param duplicate [Boolean] whether this leaf duplicates its sibling
        def initialize(offset:, hash: nil, txid: false, duplicate: false)
          @offset = offset
          @hash = hash
          @txid = txid
          @duplicate = duplicate
        end
      end

      # @return [Integer] the block height this merkle path belongs to
      attr_reader :block_height

      # @return [Array<Array<PathElement>>] tree levels, each an array of leaves
      attr_reader :path

      # @param block_height [Integer] the block height
      # @param path [Array<Array<PathElement>>] tree levels
      def initialize(block_height:, path:)
        @block_height = block_height
        @path = path
      end

      # --- Binary serialisation (BRC-74) ---

      # Deserialise a merkle path from BRC-74 binary format.
      #
      # @param data [String] binary data
      # @param offset [Integer] byte offset to start reading from
      # @return [Array(MerklePath, Integer)] the merkle path and bytes consumed
      def self.from_binary(data, offset = 0)
        start = offset

        block_height, vi_size = VarInt.decode(data, offset)
        offset += vi_size

        tree_height = data.getbyte(offset)
        offset += 1

        path = Array.new(tree_height) do
          num_leaves, vi_size = VarInt.decode(data, offset)
          offset += vi_size

          leaves = Array.new(num_leaves) do
            leaf_offset, vi_size = VarInt.decode(data, offset)
            offset += vi_size

            flags = data.getbyte(offset)
            offset += 1

            dup = flags.anybits?(0x01)
            is_txid = flags.anybits?(0x02)

            leaf_hash = nil
            unless dup
              leaf_hash = data.byteslice(offset, 32).b
              offset += 32
            end

            PathElement.new(offset: leaf_offset, hash: leaf_hash, txid: is_txid, duplicate: dup)
          end

          leaves.sort_by(&:offset)
        end

        [new(block_height: block_height, path: path), offset - start]
      end

      # Deserialise a merkle path from a BRC-74 hex string.
      #
      # @param hex [String] hex-encoded BUMP data
      # @return [MerklePath] the parsed merkle path
      def self.from_hex(hex)
        from_binary([hex].pack('H*')).first
      end

      # Serialise the merkle path to BRC-74 binary format.
      #
      # @return [String] binary BUMP data
      def to_binary
        buf = VarInt.encode(@block_height)
        buf << [@path.length].pack('C')

        @path.each do |level|
          buf << VarInt.encode(level.length)
          level.each do |leaf|
            buf << VarInt.encode(leaf.offset)
            flags = 0
            flags |= 0x01 if leaf.duplicate
            flags |= 0x02 if leaf.txid
            buf << [flags].pack('C')
            buf << leaf.hash unless leaf.duplicate
          end
        end

        buf
      end

      # Serialise the merkle path to a BRC-74 hex string.
      #
      # @return [String] hex-encoded BUMP data
      def to_hex
        to_binary.unpack1('H*')
      end

      # --- Merkle root computation ---

      # Compute the parent hash of two sibling nodes.
      #
      # @param left [String] 32-byte left child hash
      # @param right [String] 32-byte right child hash
      # @return [String] 32-byte parent hash (double-SHA-256 of concatenation)
      def self.merkle_tree_parent(left, right)
        BSV::Primitives::Digest.sha256d(left + right)
      end

      # Recompute the merkle root from this path and a transaction ID.
      #
      # @param txid [String, nil] 32-byte txid in internal byte order (auto-detected if nil)
      # @return [String] 32-byte merkle root in internal byte order
      # @raise [ArgumentError] if the txid is not found in the path
      def compute_root(txid = nil)
        txid ||= @path[0].find(&:hash)&.hash
        return txid if @path.length == 1 && @path[0].length == 1

        indexed = build_indexed_path

        tx_leaf = @path[0].find { |l| l.hash == txid }
        raise ArgumentError, 'the BUMP does not contain the txid' unless tx_leaf

        working = tx_leaf.hash
        index = tx_leaf.offset

        @path.each_with_index do |_level, height|
          sibling_offset = (index >> height) ^ 1
          sibling = offset_leaf(indexed, height, sibling_offset)
          raise ArgumentError, "missing hash at height #{height}" unless sibling

          working = if sibling.duplicate
                      self.class.merkle_tree_parent(working, working)
                    elsif sibling_offset.odd?
                      self.class.merkle_tree_parent(working, sibling.hash)
                    else
                      self.class.merkle_tree_parent(sibling.hash, working)
                    end
        end

        working
      end

      # Recompute the merkle root and return it as a hex string.
      #
      # @param txid_hex [String, nil] hex-encoded txid (display order)
      # @return [String] hex-encoded merkle root (display order)
      def compute_root_hex(txid_hex = nil)
        txid = txid_hex ? [txid_hex].pack('H*').reverse : nil
        compute_root(txid).reverse.unpack1('H*')
      end

      # --- Verification ---

      # Verify that this merkle path is valid for a given transaction.
      #
      # Computes the merkle root from the path and txid, then checks it
      # against the blockchain via the provided chain tracker.
      #
      # @param txid_hex [String] hex-encoded transaction ID (display order)
      # @param chain_tracker [ChainTracker] chain tracker to verify the root against
      # @return [Boolean] true if the computed root matches the block at this height
      def verify(txid_hex, chain_tracker)
        root_hex = compute_root_hex(txid_hex)
        chain_tracker.valid_root_for_height?(root_hex, @block_height)
      end

      # --- Combine ---

      # Merge another merkle path into this one.
      #
      # Both paths must share the same block height and merkle root.
      # After combining, this path contains the union of all leaves.
      #
      # @param other [MerklePath] the path to merge in
      # @return [self] for chaining
      # @raise [ArgumentError] if block heights or merkle roots differ
      def combine(other)
        raise ArgumentError, 'block heights differ' unless @block_height == other.block_height

        root1 = compute_root
        root2 = other.compute_root
        raise ArgumentError, 'merkle roots differ' unless root1 == root2

        max_levels = [@path.length, other.path.length].max
        max_levels.times do |h|
          @path << [] if h >= @path.length
          next if h >= other.path.length

          existing = @path[h].to_h { |e| [e.offset, e] }
          other.path[h].each do |elem|
            existing[elem.offset] ||= elem
          end
          @path[h] = existing.values.sort_by(&:offset)
        end

        self
      end

      private

      def build_indexed_path
        @path.map do |level|
          level.to_h { |elem| [elem.offset, elem] }
        end
      end

      def offset_leaf(indexed, level, offset)
        return indexed[level][offset] if indexed[level]&.key?(offset)
        return if level.zero?

        left = offset_leaf(indexed, level - 1, offset * 2)
        right = offset_leaf(indexed, level - 1, (offset * 2) + 1)
        return unless left&.hash && right

        hash = if right.duplicate
                 self.class.merkle_tree_parent(left.hash, left.hash)
               else
                 self.class.merkle_tree_parent(left.hash, right.hash)
               end

        elem = PathElement.new(offset: offset, hash: hash)
        indexed[level] ||= {}
        indexed[level][offset] = elem
        elem
      end
    end
  end
end
