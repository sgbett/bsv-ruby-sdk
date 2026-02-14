# frozen_string_literal: true

require 'securerandom'
require_relative 'mnemonic/wordlist'

module BSV
  module Primitives
    # BIP-39 mnemonic phrase generation and seed derivation.
    #
    # Generates human-readable mnemonic phrases from random entropy,
    # validates existing phrases (word count, vocabulary, checksum),
    # and derives 512-bit seeds for HD key generation via PBKDF2.
    #
    # @example Generate a mnemonic and derive a master key
    #   mnemonic = BSV::Primitives::Mnemonic.generate
    #   mnemonic.phrase #=> "abandon ability able ..."
    #   master = mnemonic.to_extended_key
    #   master.derive_path("m/44'/0'/0'/0/0")
    #
    # @example Import an existing mnemonic phrase
    #   mnemonic = BSV::Primitives::Mnemonic.from_phrase('zoo zoo ... wrong')
    #   mnemonic.valid? #=> true
    class Mnemonic
      # Valid entropy strengths in bits (128 = 12 words, 256 = 24 words).
      VALID_STRENGTHS = [128, 160, 192, 224, 256].freeze

      # PBKDF2 iteration count per BIP-39 specification.
      PBKDF2_ITERATIONS = 2048

      # Output key length in bytes for PBKDF2 (512 bits).
      PBKDF2_KEY_LENGTH = 64

      # @return [String] the space-separated mnemonic phrase
      attr_reader :phrase

      # @return [Array<String>] the individual mnemonic words
      attr_reader :words

      # Generate a new random mnemonic phrase.
      #
      # @param strength [Integer] entropy bits (128, 160, 192, 224, or 256)
      # @return [Mnemonic] a new mnemonic with valid checksum
      # @raise [ArgumentError] if strength is not a valid value
      def self.generate(strength: 128)
        unless VALID_STRENGTHS.include?(strength)
          raise ArgumentError, "invalid strength: #{strength}. Must be one of #{VALID_STRENGTHS.join(', ')}"
        end

        entropy = SecureRandom.random_bytes(strength / 8)
        from_entropy(entropy)
      end

      # Create a mnemonic from raw entropy bytes.
      #
      # @param entropy [String] 16, 20, 24, 28, or 32 bytes of entropy
      # @return [Mnemonic]
      # @raise [ArgumentError] if entropy length is invalid
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

      # Import and validate an existing mnemonic phrase.
      #
      # Normalises the phrase (NFKD, whitespace), validates word count,
      # vocabulary, and checksum.
      #
      # @param phrase [String] space-separated mnemonic words
      # @return [Mnemonic]
      # @raise [ArgumentError] if word count, vocabulary, or checksum is invalid
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

      # Derive a 512-bit seed from this mnemonic using PBKDF2-HMAC-SHA-512.
      #
      # @param passphrase [String] optional passphrase (default: empty string)
      # @return [String] 64-byte seed
      def to_seed(passphrase: '')
        normalised_phrase = @phrase.unicode_normalize(:nfkd)
        normalised_passphrase = passphrase.unicode_normalize(:nfkd)
        salt = "mnemonic#{normalised_passphrase}"

        Digest.pbkdf2_hmac_sha512(
          normalised_phrase, salt,
          iterations: PBKDF2_ITERATIONS, key_length: PBKDF2_KEY_LENGTH
        )
      end

      # Derive a BIP-32 master extended key from this mnemonic.
      #
      # Convenience method equivalent to +ExtendedKey.from_seed(to_seed)+.
      #
      # @param passphrase [String] optional BIP-39 passphrase
      # @param network [Symbol] +:mainnet+ or +:testnet+
      # @return [ExtendedKey] the master private extended key
      def to_extended_key(passphrase: '', network: :mainnet)
        ExtendedKey.from_seed(to_seed(passphrase: passphrase), network: network)
      end

      # Extract the original entropy bytes from this mnemonic.
      #
      # @return [String] the entropy bytes
      def to_entropy
        indices = @words.map { |w| ENGLISH_WORD_MAP[w] }
        all_bits = indices.map { |i| i.to_s(2).rjust(11, '0') }.join

        entropy_bit_count = (@words.length * 11 * 32) / 33
        entropy_bits = all_bits[0, entropy_bit_count]

        entropy_bits.chars.each_slice(8).map { |byte| byte.join.to_i(2) }.pack('C*')
      end

      # Validate the mnemonic's word count, vocabulary, and checksum.
      #
      # @return [Boolean] +true+ if the mnemonic is valid
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

      # @return [String] the mnemonic phrase
      def to_s
        @phrase
      end

      # @param other [Object] the object to compare
      # @return [Boolean] +true+ if both mnemonics have the same phrase
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
