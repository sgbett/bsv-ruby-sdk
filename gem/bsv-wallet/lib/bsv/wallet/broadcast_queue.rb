# frozen_string_literal: true

module BSV
  module Wallet
    # Duck-typed broadcast queue interface for wallet transaction dispatch.
    #
    # Include this module in broadcast queue adapters and override all instance
    # methods that raise +NotImplementedError+. The +async?+ method may be
    # overridden to return +true+ for adapters that defer execution to a
    # background worker.
    #
    # == Payload contract
    #
    # The +enqueue+ method receives a +Hash+ with the following keys:
    #
    #   {
    #     tx:                       BSV::Transaction,  # signed transaction object
    #     txid:                     String,            # hex txid
    #     beef_binary:              String,            # raw BEEF bytes
    #     input_outpoints:          Array<String>,     # locked input outpoints (nil on finalize path)
    #     change_outpoints:         Array<String>,     # change outpoints (nil on finalize path)
    #     fund_ref:                 String,            # fund reference for rollback (nil on finalize path)
    #     accept_delayed_broadcast: Boolean            # from caller options
    #   }
    #
    # When +input_outpoints+ is +nil+, the caller is on the finalize path and
    # the adapter must skip UTXO state transitions.
    #
    # == Example
    #
    #   class MyQueue
    #     include BSV::Wallet::BroadcastQueue
    #
    #     def async?
    #       true
    #     end
    #
    #     def enqueue(payload)
    #       MyWorker.perform_later(payload[:txid])
    #       { txid: payload[:txid] }
    #     end
    #
    #     def status(txid)
    #       MyWorker.status_for(txid)
    #     end
    #   end
    module BroadcastQueue
      # Enqueues a transaction for broadcast and state promotion.
      #
      # For synchronous adapters this executes immediately and returns the
      # result. For asynchronous adapters this persists the job and returns
      # a partial result; the caller should treat the action as pending.
      #
      # @param _payload [Hash] broadcast payload (see module-level doc for keys)
      # @return [Hash] result hash containing at minimum +:txid+
      # @raise [NotImplementedError] unless overridden by the including class
      def enqueue(_payload)
        raise NotImplementedError, "#{self.class}#enqueue not implemented"
      end

      # Returns +false+ by default, indicating synchronous execution.
      #
      # Override and return +true+ in adapters that defer broadcast to a
      # background worker (e.g. SolidQueue, Sidekiq).
      #
      # @return [Boolean]
      def async?
        false
      end

      # Returns +false+ by default — adapters without a broadcaster cannot
      # broadcast on-chain.
      #
      # Override in adapters that hold a broadcaster reference so that
      # +Client+ can determine broadcast availability from the queue
      # alone. This is the correct delegation point because users may pass a
      # broadcaster-equipped queue (e.g.
      # +SolidQueueAdapter.new(broadcaster: arc)+) without also passing
      # +broadcaster:+ directly to +Client+.
      #
      # @return [Boolean]
      def broadcast_enabled?
        false
      end

      # Returns the broadcast status for a previously enqueued transaction.
      #
      # @param _txid [String] hex transaction identifier
      # @return [String, nil] the current status string, or +nil+ if unknown
      # @raise [NotImplementedError] unless overridden by the including class
      def status(_txid)
        raise NotImplementedError, "#{self.class}#status not implemented"
      end

      # Maps a broadcast exception to a {ReviewActionResultStatus} string.
      #
      # This shared helper is extracted from +Client#broadcast_status_for+
      # so all queue adapters can produce consistent status strings without
      # duplicating the mapping logic.
      #
      # @param error [StandardError] the exception raised during broadcast
      # @return [String] one of +'doubleSpend'+, +'invalidTx'+, +'serviceError'+
      def self.status_for_error(error)
        return 'serviceError' unless error.is_a?(BSV::Network::BroadcastError)

        arc_status = error.arc_status.to_s.upcase
        return 'doubleSpend' if arc_status == 'DOUBLE_SPEND_ATTEMPTED'

        invalid_statuses = %w[REJECTED INVALID MALFORMED MINED_IN_STALE_BLOCK]
        return 'invalidTx' if invalid_statuses.include?(arc_status) || arc_status.include?('ORPHAN')

        'serviceError'
      end
    end
  end
end
