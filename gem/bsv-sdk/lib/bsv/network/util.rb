# frozen_string_literal: true

require 'json'

module BSV
  module Network
    # Shared utility methods for protocol implementations.
    module Util
      # Parse JSON, returning a hash with a 'detail' key on parse failure.
      # When the raw input is nil or empty the detail is nil (not an empty string).
      def self.safe_parse_json(raw)
        JSON.parse(raw.to_s)
      rescue JSON::ParserError
        { 'detail' => (raw.to_s.empty? ? nil : raw.to_s) }
      end

      # Coerce a transaction input to hex.
      #
      # Accepts (in order of preference):
      # 1. Hex string — pass-through, zero conversion
      # 2. Binary string — convert to hex
      # 3. Transaction object — prefer EF hex (BRC-30), fall back to raw hex
      #
      # Detection uses content, not encoding: a string is hex if it has even
      # length and contains only hex characters. This handles hex strings
      # tagged as ASCII-8BIT (e.g. read from IO in binary mode).
      #
      # @param tx [String, #to_ef_hex, #to_hex] transaction in any supported form
      # @return [String] hex-encoded transaction
      def self.resolve_tx_hex(tx)
        if tx.is_a?(String)
          return tx if tx.match?(/\A[0-9a-fA-F]*\z/) && tx.length.even?

          return tx.unpack1('H*')
        end

        tx.to_ef_hex
      rescue ArgumentError => e
        BSV.logger&.debug { "[Network::Util] EF serialisation failed: #{e.message} — falling back to raw hex" }
        tx.to_hex
      end
    end
  end
end
