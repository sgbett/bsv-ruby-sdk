# frozen_string_literal: true

require_relative 'error'
require_relative 'script_number'

module BSV
  module Script
    class Stack # rubocop:disable Metrics/ClassLength
      def initialize
        @items = []
      end

      # --- Push ---

      def push_bytes(data)
        @items.push(data.b)
      end

      def push_int(script_number)
        @items.push(script_number.to_bytes)
      end

      def push_bool(val)
        @items.push(val ? "\x01".b : ''.b)
      end

      # --- Pop ---

      def pop_bytes
        stack_error!('stack empty') if @items.empty?

        @items.pop
      end

      def pop_int(max_length: ScriptNumber::MAX_BYTE_LENGTH, require_minimal: false)
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

      def peek_int(idx = 0, max_length: ScriptNumber::MAX_BYTE_LENGTH, require_minimal: false)
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
        count.times { |i| @items.push(@items[start + i].dup) }
      end

      # Remove the top N items.
      def drop_n(count)
        check_count!(count, 'drop_n')
        stack_error!("stack too small for drop_n(#{count})") if @items.length < count

        @items.pop(count)
        nil
      end

      # Remove item at offset idx from top (0 = top).
      def nip_n(idx)
        check_index!(idx)

        @items.delete_at(@items.length - 1 - idx)
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
        count.times { |i| @items.push(@items[start + i].dup) }
      end

      # Copy item at index n to top (0 = top).
      def pick_n(idx)
        check_index!(idx)

        @items.push(@items[@items.length - 1 - idx].dup)
      end

      # Move item at index n to top (0 = top).
      def roll_n(idx)
        check_index!(idx)

        val = @items.delete_at(@items.length - 1 - idx)
        @items.push(val)
      end

      # Copy top and insert before second: [x1 x2] -> [x2 x1 x2]
      def tuck
        stack_error!('stack too small for tuck') if @items.length < 2

        @items.insert(@items.length - 2, @items.last.dup)
      end

      # --- Boolean conversion ---

      # Bitcoin consensus boolean: false if empty, all-zero, or negative zero (0x80 last byte).
      def self.cast_bool(bytes) # rubocop:disable Naming/PredicateMethod
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
