# frozen_string_literal: true

module BSV
  module Attest
    class Response
      attr_reader :hash, :transaction, :txid

      def initialize(hash:, transaction:, txid:)
        @hash = hash
        @transaction = transaction
        @txid = txid
      end

      def hash_hex
        @hash.unpack1('H*')
      end
    end
  end
end
