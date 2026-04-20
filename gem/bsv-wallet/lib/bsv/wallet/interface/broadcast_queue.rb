# frozen_string_literal: true

module BSV
  module Wallet
    module Interface
      # Duck-typed broadcast queue interface for wallet transaction dispatch.
      #
      # Include this module in broadcast queue adapters and override the
      # methods your adapter supports.
      module BroadcastQueue
        # Enqueues a transaction for broadcast and state promotion.
        #
        # @param _payload [Hash] broadcast payload
        # @return [Hash] result hash containing at minimum +:txid+
        def enqueue(_payload)
          raise NotImplementedError, "#{self.class}#enqueue not implemented"
        end

        # Returns +false+ by default (synchronous execution).
        # Override to return +true+ for async adapters.
        def async?
          false
        end

        # Returns +false+ by default.
        # Override in adapters that hold a broadcaster reference.
        def broadcast_enabled?
          false
        end

        # Returns the broadcast status for a previously enqueued transaction.
        #
        # @param _txid [String] hex transaction identifier
        # @return [String, nil] status string, or +nil+ if unknown
        def status(_txid)
          raise NotImplementedError, "#{self.class}#status not implemented"
        end
      end
    end
  end
end
