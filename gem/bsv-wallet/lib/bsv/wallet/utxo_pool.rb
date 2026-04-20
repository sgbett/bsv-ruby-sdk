# frozen_string_literal: true

module BSV
  module Wallet
    # Duck-typed UTXO pool interface for managing pre-funded outputs.
    #
    # Include this module in UTXO pool implementations and override all instance
    # methods that raise +NotImplementedError+. Implementations should follow the
    # BRC-123 UTXO management protocol.
    #
    # == State lifecycle
    #
    # Outputs in the pool transition through the following states:
    #
    #   :available  — output is ready for acquisition
    #   :locked     — output has been acquired and is reserved for a transaction
    #   :spent      — output has been confirmed spent on-chain
    #   :expired    — lock has timed out without a corresponding spend; returns to :available
    #
    # == Status return contract
    #
    # The +status+ method must return a +Hash+ with at minimum the following keys:
    #
    #   {
    #     pool_name:  String,  # identifier for this pool instance
    #     available:  Integer, # count of outputs in :available state
    #     locked:     Integer, # count of outputs in :locked state
    #     total:      Integer  # total managed outputs (available + locked + other)
    #   }
    #
    # == Example
    #
    #   class MyPool
    #     include BSV::Wallet::UTXOPool
    #
    #     def acquire
    #       output = @store.next_available or raise BSV::Wallet::PoolDepletedError, pool_name
    #       @store.lock(output)
    #       output
    #     end
    #
    #     def release(outpoint)
    #       @store.unlock(outpoint)
    #     end
    #
    #     def status
    #       { pool_name: pool_name, available: @store.available_count,
    #         locked: @store.locked_count, total: @store.total_count }
    #     end
    #
    #     def shutdown
    #       @store.flush
    #     end
    #   end
    module UTXOPool
      # Maximum number of acquisition retries before raising +PoolDepletedError+.
      MAX_RETRIES = 3

      # Acquires an available output from the pool, marking it as locked.
      #
      # Implementations must be safe to call concurrently. If no output is
      # available after exhausting retries, raise {PoolDepletedError}.
      #
      # @return [Hash] outpoint hash with at minimum +:txid+ (String) and
      #   +:vout+ (Integer) keys
      # @raise [PoolDepletedError] when no outputs are available
      # @raise [NotImplementedError] unless overridden by the including class
      def acquire
        raise NotImplementedError, "#{self.class}#acquire not implemented"
      end

      # Releases a previously acquired output back to the pool.
      #
      # Called when a transaction using this output is rolled back or when the
      # lock period expires. The output transitions from +:locked+ back to
      # +:available+.
      #
      # @param _outpoint [Hash] outpoint hash with +:txid+ and +:vout+ keys
      # @return [void]
      # @raise [NotImplementedError] unless overridden by the including class
      def release(_outpoint)
        raise NotImplementedError, "#{self.class}#release not implemented"
      end

      # Returns a status summary for this pool instance.
      #
      # The returned hash must include at minimum the keys documented in the
      # module-level status contract.
      #
      # @return [Hash] pool status summary (see module-level doc for keys)
      # @raise [NotImplementedError] unless overridden by the including class
      def status
        raise NotImplementedError, "#{self.class}#status not implemented"
      end

      # Shuts down the pool, releasing all held resources.
      #
      # Called during graceful shutdown to flush pending state, close
      # connections, and stop background threads. After +shutdown+, the pool
      # must not be used.
      #
      # @return [void]
      # @raise [NotImplementedError] unless overridden by the including class
      def shutdown
        raise NotImplementedError, "#{self.class}#shutdown not implemented"
      end
    end
  end
end
