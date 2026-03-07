# frozen_string_literal: true

module BSV
  module Network
    class BroadcastResponse
      attr_reader :txid, :tx_status, :message, :extra_info, :block_hash, :block_height, :timestamp, :competing_txs

      def initialize(attrs = {})
        @txid = attrs[:txid]
        @tx_status = attrs[:tx_status]
        @message = attrs[:message]
        @extra_info = attrs[:extra_info]
        @block_hash = attrs[:block_hash]
        @block_height = attrs[:block_height]
        @timestamp = attrs[:timestamp]
        @competing_txs = attrs[:competing_txs]
      end

      def success?
        true
      end

      def mined?
        tx_status == 'MINED'
      end
    end
  end
end
