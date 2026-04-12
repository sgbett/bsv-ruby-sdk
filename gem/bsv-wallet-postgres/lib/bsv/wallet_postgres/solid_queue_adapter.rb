# frozen_string_literal: true

require 'sequel'

module BSV
  module Wallet
    # PostgreSQL-backed asynchronous broadcast queue adapter.
    #
    # Persists outbound transactions to the +wallet_broadcast_jobs+ table and
    # processes them in a background worker thread. Designed for multi-process
    # deployments where +InlineQueue+'s synchronous broadcast is unacceptable.
    #
    # The worker uses +SELECT ... FOR UPDATE SKIP LOCKED+ so multiple processes
    # can run +SolidQueueAdapter+ against the same database safely — only one
    # worker will claim a given job.
    #
    # === Lifecycle
    #
    #   adapter = BSV::Wallet::SolidQueueAdapter.new(
    #     db: sequel_db,
    #     storage: postgres_store,
    #     broadcaster: arc_broadcaster
    #   )
    #   adapter.start   # spawns background worker thread
    #   # ... process transactions ...
    #   adapter.drain   # stop + join (blocks until current poll cycle completes)
    #
    # === Recovery
    #
    # On restart, the worker's first poll naturally finds stale +sending+ jobs
    # (those whose +locked_at+ is older than +stale_threshold+ seconds) and
    # re-broadcasts them. No special recovery code is needed.
    #
    # === Drain warning
    #
    # +drain+ blocks until the current poll cycle completes. If a job is
    # mid-broadcast this may take several seconds. Jobs enqueued after
    # +@running = false+ but before the worker thread exits will remain
    # +unsent+ until the next +start+.
    class SolidQueueAdapter
      include BSV::Wallet::BroadcastQueue

      # Default number of seconds between poll cycles.
      DEFAULT_POLL_INTERVAL = 8

      # Default number of seconds before a +sending+ job is considered stale
      # and eligible for retry. Configurable for testability.
      STALE_THRESHOLD = 300

      # Maximum number of broadcast attempts before a job is abandoned.
      # After this many failures the job remains +failed+ permanently.
      MAX_ATTEMPTS = 5

      # @param db [Sequel::Database] a Sequel database handle (shared with PostgresStore)
      # @param storage [StorageAdapter] wallet storage adapter (must not be MemoryStore)
      # @param broadcaster [#broadcast] broadcaster object
      # @param poll_interval [Integer] seconds between worker poll cycles
      # @param stale_threshold [Integer] seconds before a +sending+ job is retried
      # @raise [ArgumentError] if +storage+ is a +BSV::Wallet::MemoryStore+
      # @raise [ArgumentError] if +broadcaster+ is +nil+
      def initialize(db:, storage:, broadcaster:, poll_interval: DEFAULT_POLL_INTERVAL, stale_threshold: STALE_THRESHOLD)
        if storage.is_a?(BSV::Wallet::MemoryStore)
          raise ArgumentError, 'SolidQueueAdapter requires a persistent storage adapter — MemoryStore is not supported'
        end
        raise ArgumentError, 'SolidQueueAdapter requires a broadcaster' if broadcaster.nil?

        @db             = db
        @storage        = storage
        @broadcaster    = broadcaster
        @poll_interval  = poll_interval
        @stale_threshold = stale_threshold

        @mutex         = Mutex.new
        @running       = false
        @worker_thread = nil
      end

      # Returns +true+ — this adapter executes broadcast asynchronously.
      #
      # @return [Boolean]
      def async?
        true
      end

      # Persists a transaction to the broadcast job queue and returns immediately.
      #
      # Inserts a row into +wallet_broadcast_jobs+ with status +unsent+. If a row
      # already exists for the same +txid+ (e.g. after a crash and restart), the
      # +UniqueConstraintViolation+ is rescued and the existing status is returned
      # instead.
      #
      # @param payload [Hash] broadcast payload (see +BroadcastQueue+ module docs)
      # @return [Hash] +{ txid: String, broadcast_status: 'sending' }+
      def enqueue(payload)
        txid             = payload[:txid]
        beef_binary      = payload[:beef_binary]
        input_outpoints  = payload[:input_outpoints]
        change_outpoints = payload[:change_outpoints]
        fund_ref         = payload[:fund_ref]

        row = {
          txid: txid,
          beef_hex: beef_binary.unpack1('H*'),
          input_outpoints: input_outpoints ? Sequel.pg_array(input_outpoints, :text) : nil,
          change_outpoints: change_outpoints ? Sequel.pg_array(change_outpoints, :text) : nil,
          fund_ref: fund_ref,
          status: 'unsent'
        }

        begin
          @db[:wallet_broadcast_jobs].insert(row)
        rescue Sequel::UniqueConstraintViolation
          existing_status = @db[:wallet_broadcast_jobs].where(txid: txid).get(:status)
          return { txid: txid, broadcast_status: existing_status || 'sending' }
        end

        { txid: txid, broadcast_status: 'sending' }
      end

      # Returns the broadcast status for a previously enqueued transaction.
      #
      # Reads directly from the jobs table — the authoritative source of truth
      # for async broadcast status.
      #
      # @param txid [String] hex transaction identifier
      # @return [String, nil] status string or +nil+ if no job exists
      def status(txid)
        @db[:wallet_broadcast_jobs].where(txid: txid).get(:status)
      end

      # Spawns the background worker thread.
      #
      # Safe to call multiple times — returns immediately if already running.
      #
      # @return [void]
      def start
        return if running?

        @mutex.synchronize { @running = true }
        @worker_thread = Thread.new { worker_loop }
      end

      # Signals the worker to stop after the current poll cycle.
      #
      # Non-blocking — returns immediately without waiting for the thread.
      #
      # @return [void]
      def stop
        @mutex.synchronize { @running = false }
      end

      # Stops the worker and blocks until the current poll cycle completes.
      #
      # Safe to call when +start+ has not been called (+@worker_thread+ is nil).
      #
      # @return [void]
      def drain
        stop
        @worker_thread&.join
      end

      private

      # Main loop for the background worker thread.
      #
      # Calls +poll_once+ in a loop, sleeping +poll_interval+ seconds between
      # cycles. Unexpected errors from +poll_once+ are logged to stderr and the
      # loop continues — the worker thread must not die silently.
      def worker_loop
        while running?
          begin
            poll_once
          rescue StandardError => e
            warn "[bsv-wallet] SolidQueueAdapter worker error: #{e.message}"
          end
          sleep(@poll_interval) if running?
        end
      end

      # Thread-safe check of the running flag.
      #
      # @return [Boolean]
      def running?
        @mutex.synchronize { @running }
      end

      # Claims and processes a single pending broadcast job.
      #
      # Uses +SELECT ... FOR UPDATE SKIP LOCKED+ so concurrent workers do not
      # double-process the same job. Stale +sending+ jobs (those whose +locked_at+
      # is older than +stale_threshold+ seconds) are also eligible for retry,
      # up to +MAX_ATTEMPTS+.
      #
      # NOTE: The entire +process_job+ call (including the network broadcast)
      # runs inside this transaction, holding the row lock and a database
      # connection for the duration. This is acceptable for a single worker
      # thread with an 8-second poll interval but would need restructuring
      # for high-throughput multi-worker deployments.
      #
      # @return [void]
      def poll_once
        @db.transaction do
          job = @db[:wallet_broadcast_jobs]
                .where(Sequel.lit(
                         "status = 'unsent' OR " \
                         "(status = 'sending' AND locked_at < NOW() - " \
                         "#{@stale_threshold.to_i} * interval '1 second' " \
                         "AND attempts < #{MAX_ATTEMPTS})"
                       ))
                .order(:created_at)
                .limit(1)
                .for_update
                .skip_locked
                .first
          return unless job

          process_job(job)
        end
      end

      # Marks a job as +sending+, broadcasts the transaction, and promotes or
      # rolls back wallet state based on the outcome.
      #
      # @param job [Hash] row from +wallet_broadcast_jobs+
      # @return [void]
      def process_job(job)
        @db[:wallet_broadcast_jobs].where(id: job[:id]).update(
          status: 'sending',
          locked_at: Sequel.lit('NOW()'),
          attempts: Sequel.lit('attempts + 1'),
          updated_at: Sequel.lit('NOW()')
        )

        tx = BSV::Transaction::Transaction.from_beef_hex(job[:beef_hex])

        input_outpoints  = job[:input_outpoints]&.to_a
        change_outpoints = job[:change_outpoints]&.to_a
        txid             = job[:txid]
        fund_ref         = job[:fund_ref]

        begin
          @broadcaster.broadcast(tx)
        rescue StandardError => e
          if input_outpoints && !input_outpoints.empty?
            rollback(input_outpoints, change_outpoints, txid, fund_ref)
          elsif txid
            @storage.update_action_status(txid, 'failed')
          end
          @db[:wallet_broadcast_jobs].where(id: job[:id]).update(
            status: 'failed',
            last_error: e.message,
            updated_at: Sequel.lit('NOW()')
          )
          return
        end

        promote(input_outpoints, change_outpoints, txid)
        @db[:wallet_broadcast_jobs].where(id: job[:id]).update(
          status: 'completed',
          updated_at: Sequel.lit('NOW()')
        )
      end

      # Promotes UTXO state after a successful broadcast.
      #
      # Marks inputs as +:spent+, change as +:spendable+, and updates the action
      # status to +completed+. When outpoints are +nil+ (finalize path), UTXO
      # transitions are skipped.
      #
      # @param input_outpoints [Array<String>, nil]
      # @param change_outpoints [Array<String>, nil]
      # @param txid [String, nil]
      def promote(input_outpoints, change_outpoints, txid)
        Array(input_outpoints).each { |op| @storage.update_output_state(op, :spent) }
        Array(change_outpoints).each { |op| @storage.update_output_state(op, :spendable) }
        @storage.update_action_status(txid, 'completed') if txid
      end

      # Rolls back wallet state after a failed broadcast.
      #
      # Releases locked inputs (only those matching +fund_ref+), deletes phantom
      # change outputs, and marks the action as +failed+.
      #
      # @param input_outpoints [Array<String>]
      # @param change_outpoints [Array<String>]
      # @param txid [String, nil]
      # @param fund_ref [String] fund reference used when locking inputs
      def rollback(input_outpoints, change_outpoints, txid, fund_ref)
        Array(input_outpoints).each do |op|
          outputs = @storage.find_outputs({ outpoint: op, include_spent: true, limit: 1, offset: 0 })
          next if outputs.empty?
          next unless outputs.first[:pending_reference] == fund_ref

          @storage.update_output_state(op, :spendable)
        end
        Array(change_outpoints).each { |op| @storage.delete_output(op) }
        @storage.update_action_status(txid, 'failed') if txid
      end
    end
  end
end
