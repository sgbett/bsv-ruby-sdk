# frozen_string_literal: true

module BSV
  module Transaction
    class MerklePath
      class PathElement
        attr_reader :offset, :hash, :txid, :duplicate

        def initialize(offset:, hash: nil, txid: false, duplicate: false)
          @offset = offset
          @hash = hash
          @txid = txid
          @duplicate = duplicate
        end
      end

      attr_reader :block_height, :path

      def initialize(block_height:, path:)
        @block_height = block_height
        @path = path
      end

      # --- Binary serialisation (BRC-74) ---

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

      def self.from_hex(hex)
        from_binary([hex].pack('H*')).first
      end

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

      def to_hex
        to_binary.unpack1('H*')
      end

      # --- Merkle root computation ---

      def self.merkle_tree_parent(left, right)
        BSV::Primitives::Digest.sha256d(left + right)
      end

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

      def compute_root_hex(txid_hex = nil)
        txid = txid_hex ? [txid_hex].pack('H*').reverse : nil
        compute_root(txid).reverse.unpack1('H*')
      end

      # --- Combine ---

      def combine(other)
        raise ArgumentError, 'block heights differ' unless @block_height == other.block_height

        root1 = compute_root
        root2 = other.compute_root
        raise ArgumentError, 'merkle roots differ' unless root1 == root2

        max_levels = [@path.length, other.path.length].max
        max_levels.times do |h|
          @path << [] if h >= @path.length
          next if h >= other.path.length

          existing = @path[h].each_with_object({}) { |e, m| m[e.offset] = e }
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
          level.each_with_object({}) { |elem, h| h[elem.offset] = elem }
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
