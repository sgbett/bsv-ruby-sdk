# frozen_string_literal: true

require 'securerandom'

module BSV
  module Wallet
    # In-process UTXO pool backed by the wallet's own +StorageAdapter+.
    #
    # +LocalPool+ maintains a named basket of pre-funded outputs that callers
    # can acquire for use as inputs in transactions. Acquired outputs are locked
    # via +lock_utxos+ with +no_send: true+, making them exempt from
    # +release_stale_pending!+ sweeps (bug #1 fix). Releasing an output
    # returns it to +:spendable+ state.
    #
    # When the available count drops to or below the low-water mark, +acquire+
    # signals the optional replenishment worker to top up the pool. The signal
    # uses +=+ (not +<+) so the worker is triggered exactly at the boundary
    # (bug #3 fix).
    #
    # == Thread safety
    #
    # All public methods are safe to call concurrently. +acquire+ holds the
    # storage-level mutex via +lock_utxos+, which performs an atomic
    # find-and-lock. The pool-level +@mutex+ guards +@state+ and +@replenisher+.
    #
    # == Pool basket naming
    #
    # The basket name is derived as <tt>"pool:#{name}"</tt>, placing all pool
    # outputs in the structured +pool:+ zone.
    #
    # == State values
    #
    # +status[:state]+ is one of:
    #
    #   :healthy       — pool has outputs above the low-water mark
    #   :replenishing  — pool is below low-water mark and worker is running
    #   :depleted      — pool is empty and worker cannot replenish
    #   :shutdown      — pool has been shut down
    class LocalPool
      include UTXOPool

      attr_reader :storage, :basket, :name, :target_count, :target_satoshis
      attr_writer :replenisher

      # @param name [String] pool identifier; basket becomes <tt>"pool:#{name}"</tt>
      # @param storage [StorageAdapter] wallet storage adapter
      # @param wallet_client [#create_action] wallet client for replenishment
      # @param target_count [Integer] desired number of UTXOs in the pool
      # @param target_satoshis [Integer] satoshi value per pool output
      # @param low_water_mark [Integer] available count at or below which replenishment is triggered
      def initialize(name:, storage:, wallet_client:, target_count:, target_satoshis:, low_water_mark:)
        @name             = name
        @basket           = "pool:#{name}"
        @storage          = storage
        @wallet_client    = wallet_client
        @target_count     = target_count
        @target_satoshis  = target_satoshis
        @low_water_mark   = low_water_mark
        @replenisher      = nil
        @state            = :healthy
        @mutex            = Mutex.new
      end

      # Acquires an available output from the pool and locks it.
      #
      # Finds spendable outputs in the pool basket, then atomically locks the
      # first candidate via +lock_utxos+ with +no_send: true+. On contention
      # (another thread claimed the output first), retries up to
      # {UTXOPool::MAX_RETRIES} times before raising {PoolDepletedError}.
      #
      # After a successful acquisition, signals the replenisher if the
      # available count has dropped to or below the low-water mark.
      #
      # @return [String] the locked outpoint string (<tt>"txid.vout"</tt>)
      # @raise [PoolDepletedError] when the pool is empty or all retries fail
      def acquire
        @mutex.synchronize { raise PoolDepletedError, @name if @state == :shutdown }

        MAX_RETRIES.times do
          candidates = @storage.find_spendable_outputs(basket: @basket)
          raise PoolDepletedError, @name if candidates.empty?

          outpoint  = candidates.first[:outpoint]
          reference = "pool-acquire-#{SecureRandom.hex(8)}"
          locked    = @storage.lock_utxos([outpoint], reference: reference, no_send: true)

          next if locked.empty?

          maybe_signal_replenisher(candidates.size - 1)
          return outpoint
        end

        raise PoolDepletedError, @name
      end

      # Releases a previously acquired output back to +:spendable+ state.
      #
      # @param outpoint [String] the outpoint string to release
      # @return [void]
      # @raise [BSV::Wallet::WalletError] if the outpoint is not found in storage
      def release(outpoint)
        @storage.update_output_state(outpoint, :spendable)
      end

      # Returns a summary of the pool's current state.
      #
      # @return [Hash] status hash with keys +:available+, +:target+,
      #   +:satoshis_committed+, and +:state+
      def status
        spendable = @storage.find_spendable_outputs(basket: @basket)
        {
          available: spendable.size,
          target: @target_count,
          satoshis_committed: spendable.sum { |o| o[:satoshis].to_i },
          state: current_state(spendable.size)
        }
      end

      # Shuts down the pool.
      #
      # Stops the replenishment worker if one is running and marks the pool as
      # +:shutdown+. Idempotent — safe to call more than once.
      #
      # @return [void]
      def shutdown
        @mutex.synchronize do
          return if @state == :shutdown

          @replenisher&.stop
          @state = :shutdown
        end
      end

      private

      # Signals the replenisher if the available count is at or below the
      # low-water mark.
      #
      # Uses +=+ (bug #3 fix: was +<+ in earlier versions).
      #
      # @param available [Integer] current available count after acquisition
      def maybe_signal_replenisher(available)
        return unless available <= @low_water_mark

        @mutex.synchronize do
          @state = :replenishing if @state == :healthy
          @replenisher&.signal
        end
      end

      # Resolves the effective pool state based on available count.
      #
      # Returns the stored +@state+ when +:shutdown+ or +:replenishing+;
      # otherwise derives +:healthy+ or +:depleted+ from the count.
      #
      # @param available [Integer]
      # @return [Symbol]
      def current_state(available)
        @mutex.synchronize do
          return @state if @state == :shutdown

          if available <= @low_water_mark
            @state == :replenishing ? :replenishing : :depleted
          else
            @state = :healthy
            :healthy
          end
        end
      end
    end
  end
end
