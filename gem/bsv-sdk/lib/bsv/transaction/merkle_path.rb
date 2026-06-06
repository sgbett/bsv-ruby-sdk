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
      #   @return [Boolean] BRC-74 flag — whether this leaf represents a transaction in
      #     the merkle tree (the 0x02 bit in the BRC-74 serialisation). Not a txid value.
      # @!attribute [r] duplicate
      #   @return [Boolean] whether this leaf duplicates its sibling
      class PathElement
        attr_reader :offset, :hash, :txid, :duplicate

        # @param offset [Integer] position index within the tree level
        # @param hash [String, nil] 32-byte hash (nil when duplicate)
        # @param txid [Boolean] BRC-74 flag — true when this leaf represents a transaction
        #   in the tree (the 0x02 bit in the BRC-74 serialisation). This is NOT a txid
        #   value; it is a boolean presence flag mandated by the BRC-74 specification.
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
      # @raise [ArgumentError] if block_height is negative, path is empty,
      #   any level is not an Array, or level 0 has no txid-flagged leaf
      def initialize(block_height:, path:)
        # F5.10: construction-time invariant checks
        raise ArgumentError, 'block_height must be non-negative' if block_height.negative?
        raise ArgumentError, 'path must be non-empty' if path.empty?

        path.each_with_index do |level, i|
          raise ArgumentError, "path[#{i}] must be an Array" unless level.is_a?(Array)

          level.each_with_index do |elem, j|
            raise ArgumentError, "path[#{i}][#{j}] must be a PathElement" unless elem.is_a?(PathElement)
          end
        end

        raise ArgumentError, 'level 0 of path must contain at least one txid-flagged element' unless path[0].any?(&:txid)

        @block_height = block_height
        @path = path
      end

      # Produce an independent copy: a new MerklePath whose outer +path+
      # array and each inner level array can be mutated (via {#combine},
      # {#trim}, {#extract}) without affecting the original. PathElements
      # themselves are immutable and are shared between the original and
      # the copy.
      #
      # @param source [MerklePath] the MerklePath being copied from
      # @return [void]
      def initialize_copy(source)
        super
        @path = source.path.map(&:dup)
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
        from_binary(BSV::Primitives::Hex.decode(hex, name: 'merkle path hex')).first
      end

      # Construct a MerklePath from a TSC (Bitcoin SV "Transaction Status
      # Check") merkle proof, as returned by the WhatsOnChain
      # +/tx/{txid}/proof/tsc+ endpoint.
      #
      # The TSC format gives a flat list of sibling hashes (leaf-to-root
      # order), one per tree level. BRC-74 (BUMP) requires a multi-level
      # structure with explicit tree positions. This method does the
      # conversion. Getting it wrong (e.g. flat array in a single level)
      # produces a BUMP that ARC rejects.
      #
      # @example Convert a WoC TSC proof
      #   tsc = JSON.parse(woc_response).first
      #   mp = BSV::Transaction::MerklePath.from_tsc(
      #     dtxid_hex:    tsc['txOrId'],
      #     index:        tsc['index'],
      #     nodes:        tsc['nodes'],
      #     block_height: 612_251
      #   )
      #   mp.compute_root_hex(tsc['txOrId']) #=> the block's merkle root
      #
      # @param dtxid_hex [String] hex-encoded transaction ID in display byte order
      # @param index [Integer] the transaction's position in the block
      # @param nodes [Array<String>] sibling hashes leaf-to-root, each a 32-byte
      #   hex string in display byte order, or +"*"+ for a duplicate node
      # @param block_height [Integer] the block's height (TSC carries the block
      #   hash; the caller must look up the height separately)
      # @return [MerklePath] a BRC-74 merkle path equivalent to the TSC proof
      def self.from_tsc(dtxid_hex:, index:, nodes:, block_height:)
        BSV::Primitives::Hex.validate_dtxid_hex!(dtxid_hex, name: 'dtxid_hex')
        wtxid = [dtxid_hex].pack('H*').reverse

        # Level 0 always contains the txid leaf.
        level0 = [PathElement.new(offset: index, hash: wtxid, txid: true)]

        # A single-tx block has no siblings — the txid IS the merkle root.
        return new(block_height: block_height, path: [level0]) if nodes.empty?

        # Add the txid's direct sibling at level 0.
        level0 << tsc_path_element(nodes[0], index ^ 1)
        level0.sort_by!(&:offset)

        # Levels 1..N-1 each contain one sibling (the BRC-74 minimum).
        upper_levels = nodes[1..].each_with_index.map do |node, i|
          height = i + 1
          [tsc_path_element(node, (index >> height) ^ 1)]
        end

        new(block_height: block_height, path: [level0] + upper_levels)
      end

      # Build a single PathElement from a TSC node entry.
      #
      # @param node [String] either +"*"+ (duplicate marker) or a 32-byte hex
      #   hash in display byte order
      # @param offset [Integer] tree position for this element
      # @return [PathElement]
      def self.tsc_path_element(node, offset)
        if node == '*'
          PathElement.new(offset: offset, duplicate: true)
        else
          BSV::Primitives::Hex.validate_dtxid_hex!(node, name: "TSC merkle node at offset #{offset}")
          PathElement.new(offset: offset, hash: [node].pack('H*').reverse)
        end
      end
      private_class_method :tsc_path_element

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
      # @param wtxid [String, nil] 32-byte txid in wire byte order (auto-detected if nil)
      # @return [String] 32-byte merkle root in wire byte order
      # @raise [ArgumentError] if the wtxid is not found in the path
      def compute_root(wtxid = nil)
        wtxid ||= @path[0].find(&:hash)&.hash
        BSV::Primitives::Hex.validate_wtxid!(wtxid, name: 'wtxid') if wtxid
        BSV.logger&.debug do
          dtxid = wtxid&.reverse&.unpack1('H*')
          "[MerklePath] compute_root: dtxid=#{dtxid} block_height=#{@block_height} levels=#{@path.length}"
        end
        return wtxid if @path.length == 1 && @path[0].length == 1

        indexed = build_indexed_path

        tx_leaf = @path[0].find { |l| l.hash == wtxid }
        raise ArgumentError, 'the BUMP does not contain the given wtxid' unless tx_leaf

        working = tx_leaf.hash
        index = tx_leaf.offset

        # F5.2: for compound paths where all txids are at level 0 (path.length == 1
        # or upper levels are empty/trimmed), compute up to the height implied by the
        # highest offset present in path[0]. This matches the TS SDK computeRoot logic.
        max_offset = @path[0].map(&:offset).max || 0
        tree_height = [@path.length, max_offset.bit_length].max

        tree_height.times do |height|
          sibling_offset = (index >> height) ^ 1
          sibling = offset_leaf(indexed, height, sibling_offset)

          if sibling.nil?
            # F5.2: single-level path — the sibling may be beyond the tree because
            # this is the last odd node at this height. Bitcoin Merkle duplicates it.
            if @path.length == 1 && (index >> height) == (max_offset >> height)
              working = self.class.merkle_tree_parent(working, working)
              next
            end
            raise ArgumentError, "missing hash at height #{height}"
          end

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
      # @param dtxid_hex [String, nil] hex-encoded txid (display order)
      # @return [String] hex-encoded merkle root (display order)
      def compute_root_hex(dtxid_hex = nil)
        BSV::Primitives::Hex.validate_dtxid_hex!(dtxid_hex, name: 'compute_root_hex dtxid_hex') if dtxid_hex
        wtxid = dtxid_hex ? [dtxid_hex].pack('H*').reverse : nil
        compute_root(wtxid).reverse.unpack1('H*')
      end

      # --- Verification ---

      # Verify that this merkle path is valid for a given transaction.
      #
      # Computes the merkle root from the path and txid, then checks it
      # against the blockchain via the provided chain tracker.
      #
      # For coinbase transactions (offset 0 in the merkle tree), an additional
      # maturity check is performed: the coinbase must have at least 100
      # confirmations before it is considered spendable/valid.
      #
      # NOTE: The TS SDK has an inverted coinbase maturity check at MerklePath.ts:378
      # (`this.blockHeight + 100 < height`), which rejects mature coinbase transactions
      # and accepts immature ones — the opposite of the intended behaviour. The correct
      # logic is: reject when `current_height - block_height < 100` (immature).
      #
      # @param dtxid_hex [String] hex-encoded transaction ID (display order)
      # @param chain_tracker [ChainTracker] chain tracker to verify the root against
      # @return [Boolean] true if the computed root matches the block at this height
      def verify(dtxid_hex, chain_tracker)
        BSV::Primitives::Hex.validate_dtxid_hex!(dtxid_hex, name: 'dtxid_hex')
        wtxid = [dtxid_hex].pack('H*').reverse
        tx_leaf = @path[0].find { |l| l.hash == wtxid }

        # Offset 0 in a block's merkle tree is always the coinbase transaction —
        # a Bitcoin protocol invariant. Apply the 100-block maturity check.
        if tx_leaf&.offset&.zero?
          current = chain_tracker.current_height
          return false if current - @block_height < 100
        end

        root_hex = compute_root_hex(dtxid_hex)
        valid = chain_tracker.valid_root_for_height?(root_hex, @block_height)
        BSV.logger&.debug do
          "[MerklePath] verify: dtxid=#{dtxid_hex} height=#{@block_height} root=#{root_hex} valid=#{valid}"
        end
        valid
      end

      # --- Combine ---

      # Merge another merkle path into this one.
      #
      # Both paths must share the same block height and merkle root.
      # After combining, this path contains the union of all leaves,
      # trimmed to the minimum set required to prove every txid-flagged
      # leaf. The trim matches the TS SDK's +combine+ behaviour and
      # prevents accumulation of unnecessary sibling hashes across
      # repeated merges.
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
            # Preserve txid flag when combining: if the incoming leaf is
            # flagged, never downgrade an existing entry.
            if existing.key?(elem.offset)
              existing_elem = existing[elem.offset]
              if elem.txid && !existing_elem.txid
                existing[elem.offset] = PathElement.new(
                  offset: existing_elem.offset,
                  hash: existing_elem.hash,
                  txid: true,
                  duplicate: existing_elem.duplicate
                )
              end
            else
              existing[elem.offset] = elem
            end
          end
          @path[h] = existing.values.sort_by(&:offset)
        end

        trim
        self
      end

      # --- Trim ---

      # Remove all internal nodes that are not required by level zero
      # txid-flagged leaves. Assumes the path has at least the minimum
      # set of sibling hashes needed to prove every txid leaf. Leaves
      # each level sorted by increasing offset.
      #
      # This is the Ruby port of the TypeScript SDK's +MerklePath.trim+.
      # It is called implicitly by {#combine} and {#extract} and rarely
      # needs to be invoked directly.
      #
      # @return [self] for chaining
      def trim
        @path.each { |level| level.sort_by!(&:offset) }

        computed_offsets = []
        drop_offsets = []

        @path[0].each_with_index do |node, i|
          if node.txid
            # level 0 must enable computing level 1 for every txid node
            trim_push_if_new(computed_offsets, node.offset >> 1)
          else
            # Array-index peer — works for well-formed compound BUMPs
            # where level 0 is a sequence of adjacent (txid, sibling) pairs.
            peer_index = node.offset.odd? ? i - 1 : i + 1
            peer = @path[0][peer_index] if peer_index.between?(0, @path[0].length - 1)
            # Drop non-txid level 0 nodes whose peer is also non-txid
            trim_push_if_new(drop_offsets, peer.offset) if peer && !peer.txid
          end
        end

        trim_drop_offsets_from_level(drop_offsets, 0)

        (1...@path.length).each do |h|
          drop_offsets = computed_offsets
          computed_offsets = trim_next_computed_offsets(computed_offsets)
          trim_drop_offsets_from_level(drop_offsets, h)
        end

        self
      end

      # --- Extract ---

      # Extract a minimal compound MerklePath covering only the specified
      # transaction IDs.
      #
      # Given a compound path (e.g. one merged from multiple single-leaf
      # proofs in the same block), this method reconstructs the minimum
      # set of sibling hashes at each tree level for every requested txid,
      # assembles them into a new trimmed compound path, and verifies
      # that the extracted path computes the same merkle root as the
      # source.
      #
      # The primary use case is +Tx#to_beef+: when a BUMP loaded
      # from a proof store carries +txid: true+ flags for transactions
      # that are not part of the current BEEF bundle, extracting only the
      # bundled txids strips the phantom flags (and the now-unneeded
      # sibling nodes) from the serialised output. See issue #302 for
      # background.
      #
      # Matches the TS SDK's +MerklePath.extract+ behaviour.
      #
      # @param wtxid_hashes [Array<String>] 32-byte txids in wire byte
      #   order (reverse of display order). To pass hex strings, use
      #   +dtxid_hexes.map { |h| [h].pack('H*').reverse }+.
      # @return [MerklePath] a new trimmed compound path proving only the
      #   requested txids
      # @raise [ArgumentError] if +wtxid_hashes+ is empty, any requested
      #   txid is not present in the source path's level 0, or the
      #   extracted path's root does not match the source root
      def extract(wtxid_hashes)
        raise ArgumentError, 'at least one wtxid must be provided to extract' if wtxid_hashes.empty?

        original_root = compute_root
        indexed = build_indexed_path

        # Build a level-0 hash → offset lookup
        wtxid_to_offset = {}
        @path[0].each do |leaf|
          wtxid_to_offset[leaf.hash] = leaf.offset if leaf.hash
        end

        max_offset = @path[0].map(&:offset).max || 0
        tree_height = [@path.length, max_offset.bit_length].max

        needed = Array.new(tree_height) { {} }

        wtxid_hashes.each do |wtxid_hash|
          tx_offset = wtxid_to_offset[wtxid_hash]
          if tx_offset.nil?
            raise ArgumentError,
                  "wtxid #{wtxid_hash.reverse.unpack1('H*')} not found in the Merkle Path"
          end

          # Level 0: the transaction leaf itself + its tree sibling
          needed[0][tx_offset] = PathElement.new(offset: tx_offset, hash: wtxid_hash, txid: true)
          sib0_offset = tx_offset ^ 1
          unless needed[0].key?(sib0_offset)
            sib = offset_leaf(indexed, 0, sib0_offset)
            needed[0][sib0_offset] = sib if sib
          end

          # Higher levels: just the sibling at each height
          (1...tree_height).each do |h|
            sib_offset = (tx_offset >> h) ^ 1
            next if needed[h].key?(sib_offset)

            sib = offset_leaf(indexed, h, sib_offset)
            if sib
              needed[h][sib_offset] = sib
            elsif (tx_offset >> h) == (max_offset >> h)
              # Rightmost path in a tree whose last leaf has no real sibling —
              # BRC-74 represents this as a duplicate marker.
              needed[h][sib_offset] = PathElement.new(offset: sib_offset, duplicate: true)
            end
          end
        end

        compound_path = needed.map { |level| level.values.sort_by(&:offset) }
        compound = self.class.new(block_height: @block_height, path: compound_path)
        compound.trim

        extracted_root = compound.compute_root
        unless extracted_root == original_root
          raise ArgumentError,
                "extracted path root #{extracted_root.reverse.unpack1('H*')} " \
                "does not match source root #{original_root.reverse.unpack1('H*')}"
        end

        compound
      end

      private

      def trim_push_if_new(arr, value)
        arr << value if arr.empty? || arr.last != value
      end

      def trim_drop_offsets_from_level(drop_offsets, level)
        return if drop_offsets.empty?

        drop_set = drop_offsets.to_set
        @path[level].reject! { |node| drop_set.include?(node.offset) }
      end

      def trim_next_computed_offsets(offsets)
        next_offsets = []
        offsets.each { |o| trim_push_if_new(next_offsets, o >> 1) }
        next_offsets
      end

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
