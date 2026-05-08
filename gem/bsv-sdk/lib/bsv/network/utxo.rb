# frozen_string_literal: true

module BSV
  module Network
    class UTXO
      attr_reader :tx_hash, :tx_pos, :satoshis, :height

      # @param tx_hash  [String]  transaction ID
      # @param tx_pos   [Integer] output index
      # @param satoshis [Integer] output value in satoshis (accepts +value+ as alias)
      # @param height   [Integer, nil] block height (0 or nil = unconfirmed)
      def initialize(tx_hash:, tx_pos:, satoshis: nil, value: nil, height: nil)
        @tx_hash = tx_hash
        @tx_pos = tx_pos
        @satoshis = satoshis || value
        @height = height
      end

      def ==(other)
        other.is_a?(self.class) &&
          tx_hash == other.tx_hash &&
          tx_pos == other.tx_pos
      end

      alias eql? ==

      def hash
        [tx_hash, tx_pos].hash
      end
    end
  end
end
