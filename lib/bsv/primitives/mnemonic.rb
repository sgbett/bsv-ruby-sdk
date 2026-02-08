# frozen_string_literal: true

require 'securerandom'
require_relative 'mnemonic/wordlist'

module BSV
  module Primitives
    class Mnemonic
      VALID_STRENGTHS = [128, 160, 192, 224, 256].freeze
      PBKDF2_ITERATIONS = 2048
      PBKDF2_KEY_LENGTH = 64

      attr_reader :phrase, :words

      def self.generate(strength: 128)
        unless VALID_STRENGTHS.include?(strength)
          raise ArgumentError, "invalid strength: #{strength}. Must be one of #{VALID_STRENGTHS.join(', ')}"
        end

        entropy = SecureRandom.random_bytes(strength / 8)
        from_entropy(entropy)
      end

      def self.from_entropy(entropy)
        entropy = entropy.b
        unless [16, 20, 24, 28, 32].include?(entropy.length)
          raise ArgumentError, "invalid entropy length: #{entropy.length} bytes. Must be 16, 20, 24, 28, or 32"
        end

        bits = bytes_to_bitstring(entropy)
        checksum = checksum_for(entropy)
        all_bits = bits + checksum

        word_indices = all_bits.scan(/.{11}/).map { |group| group.to_i(2) }
        words = word_indices.map { |i| ENGLISH_WORDLIST[i] }

        new(words.join(' '))
      end

      def self.from_phrase(phrase)
        normalised = phrase.unicode_normalize(:nfkd).strip.gsub(/\s+/, ' ')
        mnemonic = new(normalised)

        unless [12, 15, 18, 21, 24].include?(mnemonic.words.length)
          raise ArgumentError, "invalid word count: #{mnemonic.words.length}. Must be 12, 15, 18, 21, or 24"
        end

        mnemonic.words.each do |word|
          raise ArgumentError, "unknown word: #{word}" unless ENGLISH_WORD_MAP.key?(word)
        end

        raise ArgumentError, 'invalid checksum' unless mnemonic.valid?

        mnemonic
      end

      def to_seed(passphrase: '')
        normalised_phrase = @phrase.unicode_normalize(:nfkd)
        normalised_passphrase = passphrase.unicode_normalize(:nfkd)
        salt = "mnemonic#{normalised_passphrase}"

        Digest.pbkdf2_hmac_sha512(
          normalised_phrase, salt,
          iterations: PBKDF2_ITERATIONS, key_length: PBKDF2_KEY_LENGTH
        )
      end

      def to_extended_key(passphrase: '', network: :mainnet)
        ExtendedKey.from_seed(to_seed(passphrase: passphrase), network: network)
      end

      def to_entropy
        indices = @words.map { |w| ENGLISH_WORD_MAP[w] }
        all_bits = indices.map { |i| i.to_s(2).rjust(11, '0') }.join

        entropy_bit_count = (@words.length * 11 * 32) / 33
        entropy_bits = all_bits[0, entropy_bit_count]

        entropy_bits.chars.each_slice(8).map { |byte| byte.join.to_i(2) }.pack('C*')
      end

      def valid?
        return false unless [12, 15, 18, 21, 24].include?(@words.length)
        return false if @words.any? { |w| !ENGLISH_WORD_MAP.key?(w) }

        indices = @words.map { |w| ENGLISH_WORD_MAP[w] }
        all_bits = indices.map { |i| i.to_s(2).rjust(11, '0') }.join

        entropy_bit_count = (@words.length * 11 * 32) / 33
        checksum_bit_count = entropy_bit_count / 32

        entropy_bits = all_bits[0, entropy_bit_count]
        checksum_bits = all_bits[entropy_bit_count, checksum_bit_count]

        entropy_bytes = entropy_bits.chars.each_slice(8).map { |byte| byte.join.to_i(2) }.pack('C*')
        expected_checksum = self.class.send(:checksum_for, entropy_bytes)

        checksum_bits == expected_checksum
      end

      def to_s
        @phrase
      end

      def ==(other)
        return false unless other.is_a?(Mnemonic)

        @phrase == other.phrase
      end

      private_class_method def self.bytes_to_bitstring(bytes)
        bytes.each_byte.map { |b| b.to_s(2).rjust(8, '0') }.join
      end

      private_class_method def self.checksum_for(entropy)
        hash = Digest.sha256(entropy)
        checksum_length = entropy.length * 8 / 32
        bitstring = hash.each_byte.map { |b| b.to_s(2).rjust(8, '0') }.join
        bitstring[0, checksum_length]
      end

      private

      def initialize(phrase)
        @phrase = phrase.freeze
        @words = phrase.split.freeze
      end
    end
  end
end
