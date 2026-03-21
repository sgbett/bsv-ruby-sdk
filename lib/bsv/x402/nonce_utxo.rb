# frozen_string_literal: true

module BSV
  module X402
    # Immutable value object representing the nonce UTXO embedded in a challenge.
    #
    # The nonce UTXO is a server-issued UTXO (invariant N-2) that the client must
    # spend in the payment transaction to prove freshness and prevent replay.
    #
    # Invariant N-1: +satoshis+ must be greater than zero.
    class NonceUTXO
      # @return [String] transaction ID of the nonce UTXO
      attr_reader :txid

      # @return [Integer] output index of the nonce UTXO
      attr_reader :vout

      # @return [Integer] value of the nonce UTXO in satoshis (must be > 0)
      attr_reader :satoshis

      # @return [String] hex-encoded locking script of the nonce UTXO
      attr_reader :locking_script_hex

      # Constructs a +NonceUTXO+ from explicit field values.
      #
      # @raise [BSV::X402::ValidationError] if +satoshis+ is not positive
      def initialize(txid:, vout:, satoshis:, locking_script_hex:)
        @txid               = txid
        @vout               = vout
        @satoshis           = satoshis
        @locking_script_hex = locking_script_hex

        validate!
        freeze
      end

      # Constructs a +NonceUTXO+ from a parsed JSON hash (string or symbol keys).
      #
      # @param hash [Hash]
      # @return [NonceUTXO]
      def self.from_hash(hash)
        new(
          txid: fetch(hash, 'txid'),
          vout: fetch(hash, 'vout'),
          satoshis: fetch(hash, 'satoshis'),
          locking_script_hex: fetch(hash, 'locking_script_hex')
        )
      end

      # Returns a plain hash suitable for JSON serialisation.
      #
      # @return [Hash]
      def to_hash
        {
          'locking_script_hex' => locking_script_hex,
          'satoshis' => satoshis,
          'txid' => txid,
          'vout' => vout
        }
      end

      private

      def validate!
        raise ValidationError, 'nonce_utxo.satoshis must be greater than zero' unless satoshis.is_a?(Integer) && satoshis.positive?
      end

      def self.fetch(hash, key)
        return hash[key] if hash.key?(key)
        return hash[key.to_sym] if hash.key?(key.to_sym)

        raise ValidationError, "nonce_utxo missing required field: #{key}"
      end
      private_class_method :fetch
    end
  end
end
