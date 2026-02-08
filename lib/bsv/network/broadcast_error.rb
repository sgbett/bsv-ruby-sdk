# frozen_string_literal: true

module BSV
  module Network
    class BroadcastError < StandardError
      attr_reader :status_code, :txid

      def initialize(message, status_code: nil, txid: nil)
        @status_code = status_code
        @txid = txid
        super(message)
      end
    end
  end
end
