# frozen_string_literal: true

module BSV
  module Transaction
    # A Bitcoin transaction: a collection of inputs consuming previous outputs
    # and producing new outputs.
    #
    # Supports construction, binary/hex serialisation, BIP-143 sighash
    # computation (with FORKID), signing, script verification, and fee
    # estimation.
    #
    # @example Build, sign, and serialise a transaction
    #   tx = BSV::Transaction::Transaction.new
    #   tx.add_input(input)
    #   tx.add_output(output)
    #   tx.sign(0, private_key)
    #   tx.to_hex #=> "0100000001..."
    class Transaction
      # Estimated size of an unsigned P2PKH input in bytes.
      UNSIGNED_P2PKH_INPUT_SIZE = 148

      # @return [Integer] transaction version number
      attr_reader :version

      # @return [Integer] lock time (block height or Unix timestamp)
      attr_reader :lock_time

      # @return [Array<TransactionInput>] transaction inputs
      attr_reader :inputs

      # @return [Array<TransactionOutput>] transaction outputs
      attr_reader :outputs

      # @return [MerklePath, nil] BRC-74 merkle path (for BEEF serialisation)
      attr_accessor :merkle_path

      # @param version [Integer] transaction version (default: 1)
      # @param lock_time [Integer] lock time (default: 0)
      def initialize(version: 1, lock_time: 0)
        @version = version
        @lock_time = lock_time
        @inputs = []
        @outputs = []
        @merkle_path = nil
      end

      # Append a transaction input.
      #
      # @param input [TransactionInput] the input to add
      # @return [self] for chaining
      def add_input(input)
        @inputs << input
        self
      end

      # Append a transaction output.
      #
      # @param output [TransactionOutput] the output to add
      # @return [self] for chaining
      def add_output(output)
        @outputs << output
        self
      end

      # --- Serialisation ---

      # Serialise the transaction to its binary wire format.
      #
      # @return [String] raw transaction bytes
      def to_binary
        buf = [@version].pack('V')
        buf << VarInt.encode(@inputs.length)
        @inputs.each { |i| buf << i.to_binary }
        buf << VarInt.encode(@outputs.length)
        @outputs.each { |o| buf << o.to_binary }
        buf << [@lock_time].pack('V')
        buf
      end

      # Serialise the transaction to a hex string.
      #
      # @return [String] hex-encoded transaction
      def to_hex
        to_binary.unpack1('H*')
      end

      # Serialise the transaction in Extended Format (BRC-30).
      #
      # EF embeds source satoshis and source locking scripts in each input,
      # allowing ARC to validate sighashes without fetching parent transactions.
      #
      # @return [String] raw EF transaction bytes
      # @raise [ArgumentError] if any input is missing source_satoshis or source_locking_script
      def to_ef
        buf = [@version].pack('V')
        buf << "\x00\x00\x00\x00\x00\xEF".b
        buf << VarInt.encode(@inputs.length)
        @inputs.each do |input|
          raise ArgumentError, 'inputs must have source_satoshis for EF' if input.source_satoshis.nil?
          raise ArgumentError, 'inputs must have source_locking_script for EF' if input.source_locking_script.nil?

          buf << input.to_binary
          buf << [input.source_satoshis].pack('Q<')
          lock_bytes = input.source_locking_script.to_binary
          buf << VarInt.encode(lock_bytes.bytesize)
          buf << lock_bytes
        end
        buf << VarInt.encode(@outputs.length)
        @outputs.each { |o| buf << o.to_binary }
        buf << [@lock_time].pack('V')
        buf
      end

      # Serialise the transaction in Extended Format as a hex string.
      #
      # @return [String] hex-encoded EF transaction
      def to_ef_hex
        to_ef.unpack1('H*')
      end

      # Deserialise a transaction from binary data.
      #
      # @param data [String] raw binary transaction
      # @return [Transaction] the parsed transaction
      def self.from_binary(data)
        raise ArgumentError, "truncated transaction: need at least 10 bytes, got #{data.bytesize}" if data.bytesize < 10

        offset = 0

        version = data.byteslice(offset, 4).unpack1('V')
        offset += 4

        tx = new(version: version)

        input_count, vi_size = VarInt.decode(data, offset)
        offset += vi_size
        input_count.times do
          input, consumed = TransactionInput.from_binary(data, offset)
          tx.add_input(input)
          offset += consumed
        end

        output_count, vi_size = VarInt.decode(data, offset)
        offset += vi_size
        output_count.times do
          output, consumed = TransactionOutput.from_binary(data, offset)
          tx.add_output(output)
          offset += consumed
        end

        raise ArgumentError, "truncated transaction: need 4 bytes for lock_time at offset #{offset}, got #{data.bytesize - offset}" if data.bytesize < offset + 4

        tx.instance_variable_set(:@lock_time, data.byteslice(offset, 4).unpack1('V'))
        tx
      end

      # Deserialise a transaction from a hex string.
      #
      # @param hex [String] hex-encoded transaction
      # @return [Transaction] the parsed transaction
      def self.from_hex(hex)
        from_binary([hex].pack('H*'))
      end

      # Deserialise a transaction from Extended Format (BRC-30) binary data.
      #
      # @param data [String] raw EF binary
      # @return [Transaction] the parsed transaction with source data on inputs
      # @raise [ArgumentError] if the EF marker is invalid
      def self.from_ef(data)
        raise ArgumentError, "truncated EF transaction: need at least 10 bytes, got #{data.bytesize}" if data.bytesize < 10

        offset = 0

        version = data.byteslice(offset, 4).unpack1('V')
        offset += 4

        marker = data.byteslice(offset, 6)
        raise ArgumentError, 'invalid EF marker' unless marker == "\x00\x00\x00\x00\x00\xEF".b

        offset += 6

        tx = new(version: version)

        input_count, vi_size = VarInt.decode(data, offset)
        offset += vi_size
        input_count.times do
          input, consumed = TransactionInput.from_binary(data, offset)
          tx.add_input(input)
          offset += consumed

          raise ArgumentError, "truncated EF input: need 8 bytes for source_satoshis at offset #{offset}, got #{data.bytesize - offset}" if data.bytesize < offset + 8

          input.source_satoshis = data.byteslice(offset, 8).unpack1('Q<')
          offset += 8

          lock_len, vi_size = VarInt.decode(data, offset)
          offset += vi_size
          if lock_len.positive?
            input.source_locking_script = BSV::Script::Script.from_binary(data.byteslice(offset, lock_len))
            offset += lock_len
          end
        end

        output_count, vi_size = VarInt.decode(data, offset)
        offset += vi_size
        output_count.times do
          output, consumed = TransactionOutput.from_binary(data, offset)
          tx.add_output(output)
          offset += consumed
        end

        raise ArgumentError, "truncated EF transaction: need 4 bytes for lock_time at offset #{offset}, got #{data.bytesize - offset}" if data.bytesize < offset + 4

        tx.instance_variable_set(:@lock_time, data.byteslice(offset, 4).unpack1('V'))
        tx
      end

      # Deserialise a transaction from an Extended Format hex string.
      #
      # @param hex [String] hex-encoded EF transaction
      # @return [Transaction] the parsed transaction with source data on inputs
      def self.from_ef_hex(hex)
        from_ef([hex].pack('H*'))
      end

      # Deserialise a transaction from binary data at a given offset,
      # returning the transaction and the number of bytes consumed.
      #
      # @param data [String] binary data containing the transaction
      # @param offset [Integer] byte offset to start reading from
      # @return [Array(Transaction, Integer)] the transaction and bytes consumed
      def self.from_binary_with_offset(data, offset = 0)
        raise ArgumentError, "truncated transaction: need at least 10 bytes at offset #{offset}, got #{data.bytesize - offset}" if data.bytesize < offset + 10

        start = offset

        version = data.byteslice(offset, 4).unpack1('V')
        offset += 4

        tx = new(version: version)

        input_count, vi_size = VarInt.decode(data, offset)
        offset += vi_size
        input_count.times do
          input, consumed = TransactionInput.from_binary(data, offset)
          tx.add_input(input)
          offset += consumed
        end

        output_count, vi_size = VarInt.decode(data, offset)
        offset += vi_size
        output_count.times do
          output, consumed = TransactionOutput.from_binary(data, offset)
          tx.add_output(output)
          offset += consumed
        end

        raise ArgumentError, "truncated transaction: need 4 bytes for lock_time at offset #{offset}, got #{data.bytesize - offset}" if data.bytesize < offset + 4

        tx.instance_variable_set(:@lock_time, data.byteslice(offset, 4).unpack1('V'))
        offset += 4

        [tx, offset - start]
      end

      # --- Transaction ID ---

      # Compute the transaction ID (double-SHA-256 of the serialised tx, reversed).
      #
      # @return [String] 32-byte transaction ID in internal byte order
      def txid
        BSV::Primitives::Digest.sha256d(to_binary).reverse
      end

      # The transaction ID as a hex string (display byte order).
      #
      # @return [String] hex-encoded transaction ID
      def txid_hex
        txid.unpack1('H*')
      end

      # --- Sighash (BIP-143 with FORKID) ---

      # Build the BIP-143 sighash preimage for an input.
      #
      # Only SIGHASH_FORKID types are supported (BSV requirement).
      #
      # @param input_index [Integer] the input to compute the preimage for
      # @param sighash_type [Integer] sighash flags (default: ALL|FORKID)
      # @param subscript [Script::Script, nil] override locking script for the input
      # @return [String] the raw preimage bytes (hash this to get the sighash)
      # @raise [ArgumentError] if sighash_type does not include FORKID
      def sighash_preimage(input_index, sighash_type = Sighash::ALL_FORK_ID, subscript: nil)
        raise ArgumentError, 'only SIGHASH_FORKID types are supported' unless sighash_type & Sighash::FORK_ID != 0

        input = @inputs[input_index]
        base_type = sighash_type & Sighash::MASK
        anyone = sighash_type.anybits?(Sighash::ANYONE_CAN_PAY)

        # 1. nVersion (4 LE)
        buf = [@version].pack('V')

        # 2. hashPrevouts
        buf << hash_prevouts(anyone)

        # 3. hashSequence
        buf << hash_sequence(anyone, base_type)

        # 4. outpoint of this input (32 + 4)
        buf << input.outpoint_binary

        # 5. scriptCode of this input (varint + script)
        script_bytes = (subscript || input.source_locking_script).to_binary
        buf << VarInt.encode(script_bytes.bytesize)
        buf << script_bytes

        # 6. value of this input (8 LE)
        buf << [input.source_satoshis].pack('Q<')

        # 7. nSequence of this input (4 LE)
        buf << [input.sequence].pack('V')

        # 8. hashOutputs
        buf << hash_outputs(base_type, input_index)

        # 9. nLockTime (4 LE)
        buf << [@lock_time].pack('V')

        # 10. sighash type (4 LE) — includes FORKID flag
        buf << [sighash_type].pack('V')

        buf
      end

      # Compute the BIP-143 sighash digest for an input (double-SHA-256 of the preimage).
      #
      # @param input_index [Integer] the input to compute the sighash for
      # @param sighash_type [Integer] sighash flags (default: ALL|FORKID)
      # @param subscript [Script::Script, nil] override locking script for the input
      # @return [String] 32-byte sighash digest
      def sighash(input_index, sighash_type = Sighash::ALL_FORK_ID, subscript: nil)
        BSV::Primitives::Digest.sha256d(sighash_preimage(input_index, sighash_type, subscript: subscript))
      end

      # --- Signing ---

      # Sign a single input with a private key (P2PKH).
      #
      # Computes the sighash, signs it, and sets the unlocking script on the input.
      #
      # @param input_index [Integer] the input to sign
      # @param private_key [Primitives::PrivateKey] the signing key
      # @param sighash_type [Integer] sighash flags (default: ALL|FORKID)
      # @return [self] for chaining
      def sign(input_index, private_key, sighash_type = Sighash::ALL_FORK_ID)
        hash = sighash(input_index, sighash_type)
        signature = private_key.sign(hash)
        sig_with_hashtype = signature.to_der + [sighash_type].pack('C')
        pubkey_bytes = private_key.public_key.compressed

        @inputs[input_index].unlocking_script =
          BSV::Script::Script.p2pkh_unlock(sig_with_hashtype, pubkey_bytes)
        self
      end

      # Sign all unsigned inputs.
      #
      # For each input without an unlocking script: if the input has an
      # {UnlockingScriptTemplate}, delegates to it; otherwise falls back
      # to P2PKH signing with the given private key.
      #
      # @param private_key [Primitives::PrivateKey, nil] fallback signing key
      # @param sighash_type [Integer] sighash flags (default: ALL|FORKID)
      # @return [self] for chaining
      def sign_all(private_key = nil, sighash_type = Sighash::ALL_FORK_ID)
        @inputs.each_with_index do |input, index|
          next if input.unlocking_script

          if input.unlocking_script_template
            input.unlocking_script = input.unlocking_script_template.sign(self, index)
          elsif private_key
            sign(index, private_key, sighash_type)
          end
        end
        self
      end

      # --- Script verification ---

      # Verify the scripts of a single input using the interpreter.
      #
      # @param index [Integer] the input index to verify
      # @return [Boolean] true if the scripts evaluate successfully
      def verify_input(index)
        input = @inputs[index]
        BSV::Script::Interpreter.verify(
          tx: self,
          input_index: index,
          unlock_script: input.unlocking_script,
          lock_script: input.source_locking_script,
          satoshis: input.source_satoshis
        )
      end

      # --- Fee estimation ---

      # Sum of all input source satoshi values.
      #
      # @return [Integer] total input value in satoshis
      def total_input_satoshis
        @inputs.each_with_index do |input, idx|
          raise ArgumentError, "input #{idx} has nil source_satoshis — set it before computing totals" if input.source_satoshis.nil?
        end
        @inputs.sum(&:source_satoshis)
      end

      # Sum of all output satoshi values.
      #
      # @return [Integer] total output value in satoshis
      def total_output_satoshis
        @outputs.sum(&:satoshis)
      end

      # Estimate the mining fee based on the estimated transaction size.
      #
      # @param satoshis_per_byte [Numeric] fee rate (default: 0.5 sat/byte)
      # @return [Integer] estimated fee in satoshis (rounded up)
      def estimated_fee(satoshis_per_byte: 0.5)
        size = estimated_size
        (size * satoshis_per_byte).ceil
      end

      private

      ZERO_HASH = "\x00".b * 32
      private_constant :ZERO_HASH

      def hash_prevouts(anyone_can_pay)
        return ZERO_HASH if anyone_can_pay

        buf = @inputs.map(&:outpoint_binary).join
        BSV::Primitives::Digest.sha256d(buf)
      end

      def hash_sequence(anyone_can_pay, base_type)
        return ZERO_HASH if anyone_can_pay || base_type == Sighash::SINGLE || base_type == Sighash::NONE

        buf = @inputs.map { |i| [i.sequence].pack('V') }.join
        BSV::Primitives::Digest.sha256d(buf)
      end

      def hash_outputs(base_type, input_index)
        case base_type
        when Sighash::NONE
          ZERO_HASH
        when Sighash::SINGLE
          return ZERO_HASH if input_index >= @outputs.length

          BSV::Primitives::Digest.sha256d(@outputs[input_index].to_binary)
        else # ALL (and any non-standard base type per BIP-143)
          buf = @outputs.map(&:to_binary).join
          BSV::Primitives::Digest.sha256d(buf)
        end
      end

      def estimated_size
        size = 4 # version
        size += VarInt.encode(@inputs.length).bytesize
        @inputs.each_with_index do |input, index|
          size += if input.unlocking_script
                    input.to_binary.bytesize
                  elsif input.unlocking_script_template
                    script_len = input.unlocking_script_template.estimated_length(self, index)
                    32 + 4 + VarInt.encode(script_len).bytesize + script_len + 4
                  else
                    UNSIGNED_P2PKH_INPUT_SIZE
                  end
        end
        size += VarInt.encode(@outputs.length).bytesize
        @outputs.each { |o| size += o.to_binary.bytesize }
        size += 4 # lock_time
        size
      end
    end
  end
end
