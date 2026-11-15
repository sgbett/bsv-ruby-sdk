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
      # Empty input is rejected — an empty transaction cannot meaningfully
      # be broadcast and any downstream `rawTx: ''` body is a sign of a
      # caller bug, not valid traffic.
      #
      # @param tx [String, #to_ef_hex, #to_hex] transaction in any supported form
      # @return [String] hex-encoded transaction
      # @raise [ArgumentError] if `tx` is an empty string
      def self.resolve_tx_hex(tx)
        if tx.is_a?(String)
          raise ArgumentError, 'tx cannot be empty — refusing to construct an empty broadcast' if tx.empty?
          return tx if tx.match?(/\A[0-9a-fA-F]+\z/) && tx.length.even?

          return tx.unpack1('H*')
        end

        begin
          tx.to_ef_hex
        rescue ArgumentError => e
          BSV.logger&.debug { "[Network::Util] EF serialisation failed: #{e.message} — falling back to raw hex" }
          tx.to_hex
        end
      end

      # Longest service-supplied string kept in an error message (py-sdk uses the same bound).
      SERVICE_TEXT_LIMIT = 8000

      # Smallest possible Extended Format transaction: version, marker, two
      # zero counts and lock time.
      EF_MIN_BYTES = 16

      EF_MARKER_HEX = BSV::Transaction::Tx::EF_MARKER.unpack1('H*').freeze

      # Coerce a transaction input to Extended Format (BRC-30) hex, with no
      # fallback to plain serialisation.
      #
      # A String is taken as hex when it is (after trimming surrounding
      # whitespace) non-empty, even-length hex; otherwise it is treated as
      # binary and never trimmed, because its last bytes may legitimately be
      # 0x20 or 0x0a. Plain transactions and BEEF are rejected: the services
      # that need Extended Format refuse them.
      #
      # @param tx [String, #to_ef_hex] transaction object, hex string or binary string
      # @return [String] Extended Format hex (surrounding whitespace trimmed for hex input)
      # @raise [ArgumentError] if the input is empty, cannot be serialised as
      #   Extended Format, or is not in Extended Format
      def self.resolve_ef_hex(tx)
        hex = tx.is_a?(String) ? string_to_hex(tx) : transaction_to_ef_hex(tx)
        return hex if extended_format_hex?(hex)

        raise ArgumentError, 'Extended Format (BRC-30) transaction required; got a plain transaction or BEEF'
      end

      # Reduce a string from a remote service to bounded, printable text for
      # use in error messages. The input may be binary or invalid UTF-8.
      #
      # @param value [Object] candidate text
      # @return [String, nil] cleaned text, or nil unless +value+ is a String
      #   with printable content
      def self.service_text(value)
        return unless value.is_a?(String)

        text = value.dup.force_encoding(Encoding::UTF_8).scrub(' ')
        text = text.gsub(/[[:cntrl:]]/, ' ').squeeze(' ').strip
        text = text[0, SERVICE_TEXT_LIMIT]
        text.empty? ? nil : text
      end

      def self.string_to_hex(tx)
        raise ArgumentError, 'tx cannot be empty — refusing to construct an empty broadcast' if tx.empty?

        trimmed = tx.strip
        return trimmed if !trimmed.empty? && trimmed.length.even? && trimmed.match?(/\A[0-9a-fA-F]+\z/)

        tx.b.unpack1('H*')
      end
      private_class_method :string_to_hex

      def self.transaction_to_ef_hex(tx)
        tx.to_ef_hex
      rescue ArgumentError => e
        raise ArgumentError, "Extended Format required: #{e.message}"
      end
      private_class_method :transaction_to_ef_hex

      # A 10-byte plain transaction with no inputs or outputs and lock time
      # 0xEF000000 also carries the marker at offset 4, so length matters.
      def self.extended_format_hex?(hex)
        hex.length >= EF_MIN_BYTES * 2 && hex[8, 12].casecmp?(EF_MARKER_HEX)
      end
      private_class_method :extended_format_hex?
    end
  end
end
