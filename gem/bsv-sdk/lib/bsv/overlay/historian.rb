# frozen_string_literal: true

module BSV
  module Overlay
    # Builds a chronological history (oldest → newest) of typed values by traversing
    # a transaction's input ancestry and interpreting each output with a provided interpreter.
    #
    # The interpreter contract is: +interpreter.call(tx, output_index, ctx)+, returning the
    # typed value or +nil+. Any callable responding to +:call+ is accepted (lambda, proc,
    # method, or object).
    #
    # Traversal follows +input.source_transaction+ references recursively. Callers must
    # supply transactions whose inputs have +source_transaction+ populated.
    #
    # == Cycle safety
    #
    # Each transaction is visited at most once, tracked by its +wtxid+ (wire-order binary).
    #
    # == Value semantics
    #
    # Only +nil+ is excluded. Falsy non-nil values (+false+, +""+, +0+) are valid history
    # entries and are included in the result.
    #
    # == Caching
    #
    # An optional +history_cache+ (any +[]/[]=+ responder) caches complete history results.
    # Cache keys have the form: <tt>"#{interpreter_version}|#{dtxid_hex}|#{ctx_key}"</tt>.
    # Cached arrays are stored frozen; each retrieval returns a +dup+ to protect the cache.
    #
    # == Note
    #
    # The Ruby Historian is synchronous. There is no async/await semantics.
    class Historian
      # @param interpreter       [#call]     callable: +call(tx, output_index, ctx) → value|nil+
      # @param debug             [Boolean]   enable debug logging via +BSV.logger+
      # @param history_cache     [Hash, nil] optional cache store (+[]/[]=+ responder)
      # @param interpreter_version [String]  version tag for cache key invalidation
      # @param ctx_key_fn        [#call, nil] serialises context to a string cache key
      def initialize(interpreter, debug: false, history_cache: nil, interpreter_version: 'v1', ctx_key_fn: nil)
        @interpreter = interpreter
        @debug = debug
        @history_cache = history_cache
        @interpreter_version = interpreter_version
        @ctx_key_fn = ctx_key_fn
      end

      # Traverses input ancestry from +start_transaction+ and returns all interpreted
      # values in chronological order (oldest first).
      #
      # @param start_transaction [Transaction::Tx]
      # @param context           [Object, nil] forwarded verbatim to the interpreter
      # @return [Array] interpreted values, oldest first
      def build_history(start_transaction, context = nil)
        if @history_cache
          key = cache_key(start_transaction, context)
          cached = @history_cache[key]
          unless cached.nil?
            BSV.logger&.debug { "[Historian] History cache hit: #{key}" } if @debug
            return cached.dup
          end
        end

        history = []
        visited = {}

        traverse(start_transaction, context, history, visited)

        result = history.reverse

        if @history_cache
          key ||= cache_key(start_transaction, context)
          @history_cache[key] = result.dup.freeze
          BSV.logger&.debug { "[Historian] History cached: #{key}" } if @debug
        end

        result
      end

      private

      def cache_key(tx, context)
        ctx_key = @ctx_key_fn ? @ctx_key_fn.call(context) : context.to_s
        "#{@interpreter_version}|#{tx.dtxid_hex}|#{ctx_key}"
      end

      def traverse(tx, context, history, visited)
        id = tx.wtxid

        if visited.key?(id)
          BSV.logger&.debug { "[Historian] Skipping already visited transaction: #{tx.dtxid_hex}" } if @debug
          return
        end

        visited[id] = true

        BSV.logger&.debug { "[Historian] Processing transaction: #{tx.dtxid_hex}" } if @debug

        tx.outputs.each_with_index do |_output, index|
          value = @interpreter.call(tx, index, context)
          unless value.nil?
            history << value
            BSV.logger&.debug { "[Historian] Added value to history: #{value.inspect}" } if @debug
          end
        rescue StandardError => e
          BSV.logger&.debug { "[Historian] Failed to interpret output #{index}: #{e.message}" } if @debug
        end

        tx.inputs.each do |input|
          if input.source_transaction
            traverse(input.source_transaction, context, history, visited)
          elsif @debug
            BSV.logger&.debug { '[Historian] Input missing sourceTransaction, skipping' }
          end
        end
      end
    end
  end
end
