# frozen_string_literal: true

require_relative 'error'
require_relative 'script_number'

module BSV
  module Script
    # Script execution stack providing push/pop/peek operations for bytes,
    # integers ({ScriptNumber}), and booleans.
    #
    # Implements Forth-like stack manipulation operations (dup, drop, swap,
    # rot, over, pick, roll, tuck) parameterised by count for the multi-element
    # opcodes (OP_2DUP, OP_2SWAP, etc.).
    #
    # A 32 MB aggregate memory cap is enforced on every push, matching the
    # ts-sdk behaviour. This provides a natural bound for O(n²) opcodes such
    # as OP_MUL operating on large script numbers.
    class Stack
      # Maximum total bytes held across all stack items (32 MB).
      MAX_MEMORY_BYTES = 32 * 1024 * 1024

      def initialize
        @items = []
        @memory_usage = 0
      end

      # --- Push ---

      def push_bytes(data)
        check_memory!(data.bytesize)
        bytes = data.b
        @memory_usage += bytes.bytesize
        @items.push(bytes)
      end

      def push_int(script_number)
        push_bytes(script_number.to_bytes)
      end

      def push_bool(val)
        push_bytes(val ? "\x01".b : ''.b)
      end

      # --- Pop ---

      def pop_bytes
        stack_error!('stack empty') if @items.empty?

        item = @items.pop
        @memory_usage -= item.bytesize
        item
      end

      # Decode the top stack item as a {ScriptNumber}.
      #
      # @param max_length [Integer] maximum allowed byte length. Defaults to
      #   {ScriptNumber::MAX_BYTE_LENGTH} (750,000 bytes), matching Bitcoin's
      #   +nMaxNumSize+ constant. Post-Genesis BSV makes this configurable at
      #   the node level; the SDK uses the standard default.
      # @param require_minimal [Boolean] whether to enforce minimal encoding.
      #   Defaults to +true+ — post-Genesis BSV requires minimal encoding for
      #   script numbers.
      def pop_int(max_length: ScriptNumber::MAX_BYTE_LENGTH, require_minimal: true)
        ScriptNumber.from_bytes(pop_bytes, max_length: max_length, require_minimal: require_minimal)
      end

      def pop_bool
        self.class.cast_bool(pop_bytes)
      end

      # --- Peek ---

      def peek_bytes(idx = 0)
        check_index!(idx)

        @items[@items.length - 1 - idx]
      end

      # Decode a stack item as a {ScriptNumber} without removing it.
      #
      # @param idx [Integer] depth from the top (0 = top).
      # @param max_length [Integer] maximum allowed byte length. Defaults to
      #   {ScriptNumber::MAX_BYTE_LENGTH} (750,000 bytes), matching Bitcoin's
      #   +nMaxNumSize+ constant.
      # @param require_minimal [Boolean] whether to enforce minimal encoding.
      #   Defaults to +true+ — post-Genesis BSV requires minimal encoding.
      def peek_int(idx = 0, max_length: ScriptNumber::MAX_BYTE_LENGTH, require_minimal: true)
        ScriptNumber.from_bytes(peek_bytes(idx), max_length: max_length, require_minimal: require_minimal)
      end

      def peek_bool(idx = 0)
        self.class.cast_bool(peek_bytes(idx))
      end

      # --- Info ---

      def depth
        @items.length
      end

      def empty?
        @items.empty?
      end

      def clear
        @items.clear
        @memory_usage = 0
      end

      def to_a
        @items.dup
      end

      # --- FORTH-like operations ---

      # Duplicate the top N items.
      def dup_n(count)
        check_count!(count, 'dup_n')
        stack_error!("stack too small for dup_n(#{count})") if @items.length < count

        start = @items.length - count
        added = @items[start..].sum(&:bytesize)
        check_memory!(added)
        copies = Array.new(count) { |i| @items[start + i].dup }
        @memory_usage += added
        @items.concat(copies)
      end

      # Remove the top N items.
      def drop_n(count)
        check_count!(count, 'drop_n')
        stack_error!("stack too small for drop_n(#{count})") if @items.length < count

        removed = @items.pop(count)
        @memory_usage -= removed.sum(&:bytesize)
        nil
      end

      # Remove item at offset idx from top (0 = top).
      def nip_n(idx)
        check_index!(idx)

        removed = @items.delete_at(@items.length - 1 - idx)
        @memory_usage -= removed.bytesize
        removed
      end

      # Rotate: move the bottom N of the top 3N items to the top.
      # OP_ROT (n=1): [x1 x2 x3] -> [x2 x3 x1]
      # OP_2ROT (n=2): [x1 x2 x3 x4 x5 x6] -> [x3 x4 x5 x6 x1 x2]
      def rot_n(count)
        check_count!(count, 'rot_n')
        stack_error!("stack too small for rot_n(#{count})") if @items.length < (3 * count)

        removed = @items.slice!(@items.length - (3 * count), count)
        @items.concat(removed)
      end

      # Swap the top N items with the next N.
      # OP_SWAP (n=1): [x1 x2] -> [x2 x1]
      # OP_2SWAP (n=2): [x1 x2 x3 x4] -> [x3 x4 x1 x2]
      def swap_n(count)
        check_count!(count, 'swap_n')
        stack_error!("stack too small for swap_n(#{count})") if @items.length < (2 * count)

        count.times do |i|
          a = @items.length - count + i
          b = @items.length - (2 * count) + i
          @items[a], @items[b] = @items[b], @items[a]
        end
      end

      # Copy N items from 2N depth to top.
      # OP_OVER (n=1): [x1 x2] -> [x1 x2 x1]
      # OP_2OVER (n=2): [x1 x2 x3 x4] -> [x1 x2 x3 x4 x1 x2]
      def over_n(count)
        check_count!(count, 'over_n')
        stack_error!("stack too small for over_n(#{count})") if @items.length < (2 * count)

        start = @items.length - (2 * count)
        added = @items[start, count].sum(&:bytesize)
        check_memory!(added)
        copies = Array.new(count) { |i| @items[start + i].dup }
        @memory_usage += added
        @items.concat(copies)
      end

      # Copy item at index n to top (0 = top).
      def pick_n(idx)
        check_index!(idx)

        copy = @items[@items.length - 1 - idx].dup
        check_memory!(copy.bytesize)
        @memory_usage += copy.bytesize
        @items.push(copy)
      end

      # Move item at index n to top (0 = top). Memory usage is unchanged.
      def roll_n(idx)
        check_index!(idx)

        val = @items.delete_at(@items.length - 1 - idx)
        @items.push(val)
      end

      # Copy top and insert before second: [x1 x2] -> [x2 x1 x2]
      def tuck
        stack_error!('stack too small for tuck') if @items.length < 2

        copy = @items.last.dup
        check_memory!(copy.bytesize)
        @memory_usage += copy.bytesize
        @items.insert(@items.length - 2, copy)
      end

      # --- Boolean conversion ---

      # Bitcoin consensus boolean: false if empty, all-zero, or negative zero (0x80 last byte).
      def self.cast_bool(bytes)
        return false if bytes.nil? || bytes.empty?

        bytes.each_byte.with_index do |byte, i|
          next if byte.zero?

          # Negative zero: last byte is exactly 0x80
          return !(i == bytes.bytesize - 1 && byte == 0x80)
        end

        false
      end

      private

      def stack_error!(message)
        raise ScriptError.new(ScriptErrorCode::INVALID_STACK_OPERATION, message)
      end

      def check_memory!(additional_bytes)
        return unless @memory_usage + additional_bytes > MAX_MEMORY_BYTES

        raise ScriptError.new(
          ScriptErrorCode::STACK_MEMORY_EXCEEDED,
          "stack memory limit of #{MAX_MEMORY_BYTES} bytes exceeded"
        )
      end

      def check_index!(idx)
        return if idx >= 0 && idx < @items.length

        stack_error!("index #{idx} invalid for stack size #{@items.length}")
      end

      def check_count!(count, operation)
        return if count >= 1

        stack_error!("#{operation} requires n >= 1, got #{count}")
      end
    end
  end
end
