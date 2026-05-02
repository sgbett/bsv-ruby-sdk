# frozen_string_literal: true

module BSV
  module Network
    class BroadcastError < StandardError
      # ARC API boundary: display-order hex txid as returned by the ARC error response.
      attr_reader :status_code, :txid, :arc_status

      def initialize(message, status_code: nil, txid: nil, arc_status: nil)
        @status_code = status_code
        BSV::Primitives::Hex.validate_dtxid_hex!(txid, name: 'ARC error txid') if txid
        @txid = txid
        @arc_status = arc_status
        super(message)
      end
    end
  end
end
