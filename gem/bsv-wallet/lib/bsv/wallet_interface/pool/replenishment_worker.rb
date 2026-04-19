# frozen_string_literal: true

require 'securerandom'

module BSV
  module Wallet
    # Background thread that replenishes a {LocalPool} when it runs low.
    #
    # +ReplenishmentWorker+ loops on a condition variable with a configurable
    # interval timeout. It wakes either on timeout or when signalled by
    # {LocalPool#acquire} (via {#signal}).
    #
    # Each wake cycle computes the deficit between the pool's target count and
    # its current available count. When a deficit exists, it calls
    # {WalletClient#create_action} to fund new pool outputs.
    #
    # == BRC-29 derivation
    #
    # Pool outputs are created with fresh BRC-29 derivation metadata so
    # +auto_fund_and_create+ can later identify and spend them. The logic is
    # inlined (not delegated to {ChangeGenerator}) to keep the public API
    # surface of that class clean and avoid coupling to its private internals.
    #
    # == Thread safety
    #
    # +@mutex+ and +@cv+ guard +@running+ and the condition variable. All
    # external entry points (+start+, +stop+, +signal+) are safe to call from
    # any thread.
    #
    # == Error handling
    #
    # +replenish+ rescues both {BSV::Wallet::WalletError} and +StandardError+.
    # Errors are logged to +$stderr+ and the cycle continues — a transient
    # failure (e.g. insufficient funds) does not crash the worker thread.
    class ReplenishmentWorker
      # BRC-29 protocol identifier — matches {ChangeGenerator::BRC29_PROTOCOL_ID}.
      BRC29_PROTOCOL_ID = [2, '3241645161d8'].freeze

      # @param pool [LocalPool] the pool to replenish
      # @param wallet_client [WalletClient] wallet used to fund new outputs
      # @param interval [Integer, Float] seconds between replenishment checks (default: 60)
      def initialize(pool:, wallet_client:, interval: 60)
        @pool          = pool
        @wallet_client = wallet_client
        @interval      = interval
        @mutex         = Mutex.new
        @cv            = ConditionVariable.new
        @running       = false
        @thread        = nil
      end

      # Starts the background replenishment thread.
      #
      # Idempotent — calling +start+ when already running has no effect.
      #
      # @return [self]
      def start
        @mutex.synchronize do
          return self if @running

          @running = true
          @thread  = Thread.new { run_loop }
          @thread.abort_on_exception = false
        end
        self
      end

      # Stops the background thread.
      #
      # Sets +@running+ to +false+, wakes the thread via the condition
      # variable, and joins it with a 5-second timeout.
      #
      # @return [void]
      def stop
        @mutex.synchronize do
          @running = false
          @cv.signal
        end
        @thread&.join(5)
      end

      # Wakes the worker for an immediate replenishment check.
      #
      # Non-blocking — returns immediately whether or not the thread is sleeping.
      # Safe to call before +start+ or after +stop+.
      #
      # @return [void]
      def signal
        @mutex.synchronize { @cv.signal }
      end

      private

      # Main loop executed inside the background thread.
      #
      # Waits on the condition variable for up to +@interval+ seconds, then
      # checks whether replenishment is needed. Breaks as soon as +@running+
      # is +false+.
      #
      # Each replenishment cycle is wrapped in a rescue so that a single
      # error never kills the thread.
      def run_loop
        # Replenish immediately on start — do not sleep first.
        # A newly created pool has zero outputs; sleeping before the first
        # cycle creates a chicken-and-egg deadlock where acquire raises
        # PoolDepletedError and the signal path is never reached.
        safe_replenish

        loop do
          @mutex.synchronize { @cv.wait(@mutex, @interval) }
          break unless @running

          safe_replenish
        end
      end

      # Wraps a single replenishment cycle in error handling so that
      # transient failures never kill the background thread.
      def safe_replenish
        replenish
      rescue BSV::Wallet::WalletError => e
        warn "[ReplenishmentWorker] WalletError during replenishment: #{e.message}"
      rescue StandardError => e
        warn "[ReplenishmentWorker] Unexpected error during replenishment: #{e.message}"
      end

      # Calculates the pool deficit and funds new outputs when needed.
      #
      # Returns immediately when the pool already meets its target.
      #
      # @return [void]
      def replenish
        pool_status = @pool.status
        deficit     = @pool.target_count - pool_status[:available]
        return if deficit <= 0

        outputs = Array.new(deficit) { build_pool_output(@pool.target_satoshis) }

        @wallet_client.create_action({
                                       description: 'UTXO pool replenishment',
                                       outputs: outputs,
                                       auto_fund: true,
                                       labels: ['utxo-pool-replenishment']
                                     })
      end

      # Builds a single pool output hash with freshly derived BRC-29 metadata.
      #
      # Derivation logic is inlined from {ChangeGenerator#build_output} (which
      # is private) to avoid coupling to that class's internals. The algorithm
      # is identical: random hex prefix/suffix, derive child public key via
      # the wallet's key deriver, build a P2PKH locking script.
      #
      # The +locking_script+ value is a hex string, not a {BSV::Script::Script}
      # object, because +create_action+ validates and serialises the value as
      # hex (bug #5 / #round-1 fix).
      #
      # @param satoshis [Integer] satoshi value for the new output
      # @return [Hash]
      def build_pool_output(satoshis)
        prefix       = SecureRandom.hex(16)
        suffix       = SecureRandom.hex(16)
        identity_key = @wallet_client.key_deriver.identity_key
        key_id       = "#{prefix} #{suffix}"
        protocol_id  = BRC29_PROTOCOL_ID

        pub_key        = @wallet_client.key_deriver.derive_public_key(protocol_id, key_id, identity_key, for_self: true)
        locking_script = BSV::Script::Script.p2pkh_lock(pub_key.hash160).to_hex

        {
          locking_script: locking_script,
          satoshis: satoshis,
          output_description: 'utxo pool replenishment',
          basket: @pool.basket,
          tags: ['pool'],
          derivation_prefix: prefix,
          derivation_suffix: suffix,
          sender_identity_key: identity_key
        }
      end
    end
  end
end
