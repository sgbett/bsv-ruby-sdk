# frozen_string_literal: true

module BSV
  module Attest
    class Response
      attr_reader :hash, :txid

      def initialize(hash:, txid:)
        @hash = hash
        @txid = txid
      end

      def hash_hex
        @hash.unpack1('H*')
      end
    end
  end
end
