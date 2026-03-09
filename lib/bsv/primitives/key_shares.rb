# frozen_string_literal: true

module BSV
  module Primitives
    # A set of Shamir's Secret Sharing shares derived from a private key.
    #
    # Holds the evaluation points (shares), a reconstruction threshold, and an
    # integrity string for verifying that recombined shares produce the correct
    # key. Supports serialisation to and from a human-readable backup format.
    #
    # Backup format per share: "Base58(x).Base58(y).threshold.integrity"
    #
    # This format is compatible with the Go and TypeScript reference SDKs.
    #
    # @example Round-trip through backup format
    #   shares  = key.to_key_shares(2, 5)
    #   backup  = shares.to_backup_format
    #   rebuilt = KeyShares.from_backup_format(backup[0..1])
    #   key     = PrivateKey.from_key_shares(rebuilt)
    class KeyShares
      # @return [Array<PointInFiniteField>] the share points
      attr_reader :points

      # @return [Integer] the minimum number of shares required to reconstruct the key
      attr_reader :threshold

      # @return [String] first 8 hex characters of the Hash160 of the compressed public key
      attr_reader :integrity

      # @param points    [Array<PointInFiniteField>] share points
      # @param threshold [Integer]                   reconstruction threshold
      # @param integrity [String]                    integrity check string
      def initialize(points, threshold, integrity)
        @points    = points
        @threshold = threshold
        @integrity = integrity
      end

      # Deserialise shares from backup format strings.
      #
      # Each string must have the form "Base58(x).Base58(y).threshold.integrity".
      # All shares must agree on threshold and integrity.
      #
      # @param shares [Array<String>] backup-format share strings
      # @return [KeyShares]
      # @raise [ArgumentError] if any share is malformed or shares are inconsistent
      def self.from_backup_format(shares)
        threshold = 0
        integrity = ''
        points    = shares.each_with_index.map do |share, idx|
          parts = share.split('.', -1)
          raise ArgumentError, "invalid share format in share #{idx}: expected 4 dot-separated parts, got #{share.inspect}" unless parts.length == 4

          x_str, y_str, t_str, i_str = parts

          raise ArgumentError, "threshold not found in share #{idx}" if t_str.empty?
          raise ArgumentError, "integrity not found in share #{idx}" if i_str.empty?

          t_int = Integer(t_str)

          if idx != 0
            raise ArgumentError, "threshold mismatch in share #{idx}" unless threshold == t_int
            raise ArgumentError, "integrity mismatch in share #{idx}" unless integrity == i_str
          end

          threshold = t_int
          integrity = i_str

          PointInFiniteField.from_string("#{x_str}.#{y_str}")
        end

        new(points, threshold, integrity)
      end

      # Serialise shares to backup format strings.
      #
      # @return [Array<String>] one backup string per share point
      def to_backup_format
        @points.map { |point| "#{point}.#{@threshold}.#{@integrity}" }
      end
    end
  end
end
