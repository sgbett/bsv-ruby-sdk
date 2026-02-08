# frozen_string_literal: true

module BSV
  module Network
    class UTXO
      attr_reader :tx_hash, :tx_pos, :satoshis, :height

      def initialize(tx_hash:, tx_pos:, satoshis:, height: nil)
        @tx_hash = tx_hash
        @tx_pos = tx_pos
        @satoshis = satoshis
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
