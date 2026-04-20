# frozen_string_literal: true

module BSV
  module Wallet
    # Broadcast queue implementations. See {Interface::BroadcastQueue} for the contract.
    module BroadcastQueue
      autoload :Inline, 'bsv/wallet/broadcast_queue/inline'

      # Maps a broadcast exception to a status string.
      #
      # Shared helper so all queue adapters produce consistent status strings.
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
