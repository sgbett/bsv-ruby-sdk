# frozen_string_literal: true

module BSV
  module Primitives
    # Pure-Ruby implementation of RIPEMD-160.
    #
    # Ported from the reference C implementation by Hans Dobbertin, Antoon Bosselaers,
    # and Bart Preneel (https://homes.esat.kuleuven.be/~bosselae/ripemd160/).
    #
    # RIPEMD-160 processes data in 512-bit (64-byte) blocks with 80 rounds split
    # across two parallel paths (left and right). The five 32-bit state words are
    # initialised to standard IV constants and updated via a Merkle-Damgård
    # construction with Merkle-Damgård strengthening.
    #
    # All arithmetic is 32-bit unsigned (masked with 0xFFFFFFFF after additions).
    #
    # Usage:
    #   BSV::Primitives::Ripemd160.digest(data) # => 20-byte binary String
    class Ripemd160
      # Initial hash values (little-endian words).
      IV = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0].freeze

      # Mask for 32-bit unsigned arithmetic.
      MASK32 = 0xFFFFFFFF

      # Left-path message word selection (rounds 0-79).
      RL = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, # round 0-15
        7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8,  # round 16-31
        3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12,  # round 32-47
        1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2,  # round 48-63
        4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13   # round 64-79
      ].freeze

      # Right-path message word selection (rounds 0-79).
      RR = [
        5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12,  # round 0-15
        6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2,  # round 16-31
        15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13,  # round 32-47
        8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14,  # round 48-63
        12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11   # round 64-79
      ].freeze

      # Left-path rotation amounts (rounds 0-79).
      SL = [
        11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8,  # round 0-15
        7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12,  # round 16-31
        11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5,  # round 32-47
        11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12,  # round 48-63
        9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6   # round 64-79
      ].freeze

      # Right-path rotation amounts (rounds 0-79).
      SR = [
        8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6,  # round 0-15
        9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11,  # round 16-31
        9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5,  # round 32-47
        15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8,  # round 48-63
        8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11   # round 64-79
      ].freeze

      # Left-path round constants (K_l).
      KL = [
        0x00000000, # rounds 0-15:  f(j) = x XOR y XOR z
        0x5A827999, # rounds 16-31: f(j) = (x AND y) OR (NOT x AND z)
        0x6ED9EBA1, # rounds 32-47: f(j) = (x OR NOT y) XOR z
        0x8F1BBCDC, # rounds 48-63: f(j) = (x AND z) OR (y AND NOT z)
        0xA953FD4E  # rounds 64-79: f(j) = x XOR (y OR NOT z)
      ].freeze

      # Right-path round constants (K_r).
      KR = [
        0x50A28BE6, # rounds 0-15:  f(j) = x XOR (y OR NOT z)
        0x5C4DD124, # rounds 16-31: f(j) = (x AND z) OR (y AND NOT z)
        0x6D703EF3, # rounds 32-47: f(j) = (x OR NOT y) XOR z
        0x7A6D76E9, # rounds 48-63: f(j) = (x AND y) OR (NOT x AND z)
        0x00000000  # rounds 64-79: f(j) = x XOR y XOR z
      ].freeze

      class << self
        # Compute the RIPEMD-160 digest of +data+.
        #
        # @param data [String] input data (any encoding; treated as binary)
        # @return [String] 20-byte binary digest (ASCII-8BIT encoding)
        def digest(data)
          new(data).digest
        end
      end

      # @param data [String] input data
      # @raise [TypeError] if +data+ is not a String
      def initialize(data)
        raise TypeError, "no implicit conversion of #{data.class} into String" unless data.is_a?(String)

        @data = data.b # force binary encoding
      end

      # @return [String] 20-byte binary digest
      def digest
        state = IV.dup
        blocks, = padded_blocks
        blocks.each { |block| compress!(state, block) }
        state.pack('V5')
      end

      private

      # Pad the message and split into 16-word (512-bit) blocks.
      #
      # Padding follows the Merkle-Damgård construction:
      #   1. Append a single 0x80 byte.
      #   2. Append 0x00 bytes until length ≡ 56 (mod 64).
      #   3. Append the original bit-length as a 64-bit little-endian integer.
      #
      # @return [Array<Array<Integer>>] array of 16-element word arrays
      def padded_blocks
        bit_length = @data.bytesize * 8

        # Append 1-bit then zeros so that length ≡ 56 (mod 64).
        padded = @data.dup
        padded << "\x80".b
        padded << "\x00".b while padded.bytesize % 64 != 56

        # Append 64-bit little-endian bit length (low 32 bits then high 32 bits).
        padded << [bit_length & MASK32, (bit_length >> 32) & MASK32].pack('VV')

        blocks = []
        (padded.bytesize / 64).times do |i|
          blocks << padded.byteslice(i * 64, 64).unpack('V16')
        end
        [blocks, nil]
      end

      # Apply the RIPEMD-160 compression function to +state+ in-place.
      #
      # @param state [Array<Integer>] five 32-bit state words (mutated in-place)
      # @param words [Array<Integer>] sixteen 32-bit message words
      def compress!(state, words)
        al, bl, cl, dl, el = state
        ar, br, cr, dr, er = state

        80.times do |j|
          round = j / 16

          # Left path
          fl = nonlinear_left(round, bl, cl, dl)
          t = (al + fl + words[RL[j]] + KL[round]) & MASK32
          t = (rotl32(t, SL[j]) + el) & MASK32
          al = el
          el = dl
          dl = rotl32(cl, 10)
          cl = bl
          bl = t

          # Right path
          fr = nonlinear_right(round, br, cr, dr)
          t = (ar + fr + words[RR[j]] + KR[round]) & MASK32
          t = (rotl32(t, SR[j]) + er) & MASK32
          ar = er
          er = dr
          dr = rotl32(cr, 10)
          cr = br
          br = t
        end

        # Combine: mix right-path result with left-path and current state.
        t = (state[1] + cl + dr) & MASK32
        state[1] = (state[2] + dl + er) & MASK32
        state[2] = (state[3] + el + ar) & MASK32
        state[3] = (state[4] + al + br) & MASK32
        state[4] = (state[0] + bl + cr) & MASK32
        state[0] = t
      end

      # Non-linear function for the left path.
      #
      # @param round [Integer] 0..4 (each covers 16 of the 80 steps)
      def nonlinear_left(round, x, y, z)
        case round
        when 0 then x ^ y ^ z
        when 1 then (x & y) | (~x & z)
        when 2 then (x | ~y) ^ z
        when 3 then (x & z) | (y & ~z)
        else        x ^ (y | ~z)
        end
      end

      # Non-linear function for the right path.
      #
      # @param round [Integer] 0..4 (each covers 16 of the 80 steps)
      def nonlinear_right(round, x, y, z)
        case round
        when 0 then x ^ (y | ~z)
        when 1 then (x & z) | (y & ~z)
        when 2 then (x | ~y) ^ z
        when 3 then (x & y) | (~x & z)
        else        x ^ y ^ z
        end
      end

      # Rotate +value+ left by +count+ bits (32-bit word).
      #
      # @param value [Integer] 32-bit word (may be larger; masked internally)
      # @param count [Integer] rotation count (1..31)
      # @return [Integer] rotated 32-bit word
      def rotl32(value, count)
        value &= MASK32
        ((value << count) | (value >> (32 - count))) & MASK32
      end
    end
  end
end
