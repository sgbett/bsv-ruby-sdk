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

      # Lookup table for benford_number calculation.
      # we want float values for log10(1 + (1.0 / i)) for the 9 integers 0 < i < 10
      # in ruby this becomes: (1..9).to_a.collect{|d| Math.log10(1 + (1.0 / d)) }
      LOG10_RECIPROCAL_D_VALUES_1TO9 = [0.3010299956639812,
                                        0.17609125905568124,
                                        0.12493873660829993,
                                        0.09691001300805642,
                                        0.07918124604762482,
                                        0.06694678963061322,
                                        0.05799194697768673,
                                        0.05115252244738129,
                                        0.04575749056067514].freeze

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

        if data.bytesize < offset + 4
          raise ArgumentError, "truncated transaction: need 4 bytes for lock_time at offset #{offset}, got #{data.bytesize - offset}"
        end

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

          if data.bytesize < offset + 8
            remaining = data.bytesize - offset
            raise ArgumentError, "truncated EF input: need 8 bytes for source_satoshis at offset #{offset}, got #{remaining}"
          end

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

        if data.bytesize < offset + 4
          remaining = data.bytesize - offset
          raise ArgumentError, "truncated EF transaction: need 4 bytes for lock_time at offset #{offset}, got #{remaining}"
        end

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
        if data.bytesize < offset + 10
          raise ArgumentError, "truncated transaction: need at least 10 bytes at offset #{offset}, got #{data.bytesize - offset}"
        end

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

        if data.bytesize < offset + 4
          raise ArgumentError, "truncated transaction: need 4 bytes for lock_time at offset #{offset}, got #{data.bytesize - offset}"
        end

        tx.instance_variable_set(:@lock_time, data.byteslice(offset, 4).unpack1('V'))
        offset += 4

        [tx, offset - start]
      end

      # --- BEEF convenience methods ---

      # Serialise this transaction (with its ancestry chain and merkle proofs)
      # into a BEEF V1 binary bundle (BRC-62), the default format for ARC and
      # the reference TS SDK.
      #
      # Walks the `source_transaction` references on inputs to collect ancestors.
      # Transactions with a `merkle_path` are treated as proven leaves — their
      # ancestors are not traversed further.
      #
      # @return [String] raw BEEF V1 binary
      def to_beef
        beef = Beef.new
        ancestors = collect_ancestors

        ancestors.each do |tx|
          entry = if tx.merkle_path
                    bump_idx = beef.merge_bump(tx.merkle_path)
                    Beef::BeefTx.new(
                      format: Beef::FORMAT_RAW_TX_AND_BUMP,
                      transaction: tx,
                      bump_index: bump_idx
                    )
                  else
                    Beef::BeefTx.new(
                      format: Beef::FORMAT_RAW_TX,
                      transaction: tx
                    )
                  end
          beef.transactions << entry
        end

        beef.to_binary
      end

      # Serialise this transaction to a BEEF V2 hex string.
      #
      # @return [String] hex-encoded BEEF
      def to_beef_hex
        to_beef.unpack1('H*')
      end

      # Parse a BEEF binary bundle and return the subject transaction
      # (the last transaction in the bundle).
      #
      # @param data [String] raw BEEF binary
      # @return [Transaction] the subject transaction with ancestry wired
      def self.from_beef(data)
        beef = Beef.from_binary(data)
        last_tx_entry = beef.transactions.reverse.find(&:transaction)
        last_tx_entry&.transaction
      end

      # Parse a BEEF hex string and return the subject transaction.
      #
      # @param hex [String] hex-encoded BEEF
      # @return [Transaction] the subject transaction with ancestry wired
      def self.from_beef_hex(hex)
        from_beef([hex].pack('H*'))
      end

      # --- Transaction ID ---

      # Compute the transaction ID (double-SHA-256 of the serialised tx, byte-reversed).
      #
      # Returns display byte order (reversed from the natural hash).
      # Compare with {TransactionInput#prev_tx_id} which stores wire byte
      # order (natural hash). Use +.reverse+ to convert between the two.
      #
      # @return [String] 32-byte transaction ID in display byte order
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

      # --- SPV verification ---

      # Perform full SPV verification of this transaction and its ancestry.
      #
      # Uses a queue-based approach (matching TS/Go SDKs) to walk the
      # transaction ancestry chain:
      #
      # 1. If a transaction has a merkle path that validates against the chain
      #    tracker, it is marked verified (inputs are not re-checked).
      # 2. Otherwise, each input's scripts are executed via the interpreter,
      #    and source transactions are enqueued for verification.
      # 3. Optionally validates that the root transaction's fee meets the
      #    provided fee model.
      # 4. Checks that total outputs do not exceed total inputs.
      #
      # @param chain_tracker [ChainTracker] chain tracker for merkle root validation
      # @param fee_model [FeeModel, nil] optional fee model to validate the root transaction's fee
      # @return [true] on successful verification
      # @raise [ArgumentError] if a source transaction or unlocking script is missing
      # @raise [BSV::Script::ScriptError] if script execution fails
      # @raise [VerificationError] for merkle path failures, fee validation, or output overflow
      def verify(chain_tracker:, fee_model: nil)
        verified = {}
        queue = [self]

        until queue.empty?
          tx = queue.shift
          tx_id = tx.txid_hex
          next if verified[tx_id]

          # Merkle path short-circuit: proven transaction needs no input verification
          if tx.merkle_path
            unless tx.merkle_path.verify(tx_id, chain_tracker)
              raise VerificationError.new(:invalid_merkle_proof,
                                          "invalid merkle proof for transaction #{tx_id}")
            end

            verified[tx_id] = true
            next
          end

          # Fee validation (root transaction only)
          verify_fee(fee_model) if tx.equal?(self) && fee_model

          # Verify each input
          tx.inputs.each_with_index do |input, index|
            verify_input_requirements(tx, input, index)
            tx.verify_input(index)

            # Enqueue source transaction for verification if not yet verified
            source_tx = input.source_transaction
            queue << source_tx if source_tx && !verified[source_tx.txid_hex]
          end

          # Output ≤ input check
          verify_output_constraint(tx)

          verified[tx_id] = true
        end

        true
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

      # Estimate the serialised transaction size in bytes.
      #
      # Uses actual unlocking script size for signed inputs and template
      # estimated length for unsigned inputs.
      #
      # @return [Integer] estimated size in bytes
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

      # Compute the fee and distribute change across change outputs.
      #
      # Accepts a {FeeModel} instance, a numeric fee in satoshis, or nil
      # (defaults to {FeeModels::SatoshisPerKilobyte} at 50 sat/kB).
      #
      # After computing the fee, distributes remaining satoshis across outputs
      # marked as change. The distribution strategy is controlled by the
      # +change_distribution:+ keyword argument:
      #
      # - +:equal+ (default) — divides change equally across all change outputs,
      #   matching TS SDK default behaviour.
      # - +:random+ — Benford-inspired distribution that biases amounts towards
      #   the lower end of the available range, improving privacy by producing
      #   varied change amounts.
      #
      # If insufficient change remains, all change outputs are removed.
      #
      # @param model_or_fee [FeeModel, Integer, nil] fee model, fixed fee, or nil for default
      # @param change_distribution [Symbol] +:equal+ or +:random+ (default: +:equal+)
      # @return [self] for chaining
      # @raise [ArgumentError] if +change_distribution+ is not +:random+ or +:equal+
      def fee(model_or_fee = nil, change_distribution: :equal)
        unless %i[random equal].include?(change_distribution)
          raise ArgumentError, "invalid change_distribution #{change_distribution.inspect}; expected :random or :equal"
        end

        fee_sats = compute_fee_sats(model_or_fee)
        distribute_change(fee_sats, change_distribution)
        self
      end

      private

      def verify_input_requirements(tx, input, index)
        tx_id = tx.txid_hex
        raise ArgumentError, "input #{index} of transaction #{tx_id} has no unlocking script" if input.unlocking_script.nil?
        raise ArgumentError, "input #{index} of transaction #{tx_id} has no source locking script" if input.source_locking_script.nil?
        raise ArgumentError, "input #{index} of transaction #{tx_id} has no source satoshis" if input.source_satoshis.nil?
      end

      def verify_fee(fee_model)
        required_fee = fee_model.compute_fee(self)
        actual_fee = total_input_satoshis - total_output_satoshis
        return if actual_fee >= required_fee

        raise VerificationError.new(:insufficient_fee,
                                    "insufficient fee: transaction pays #{actual_fee} sat but fee model requires #{required_fee} sat")
      end

      def verify_output_constraint(tx)
        input_total = tx.total_input_satoshis
        output_total = tx.total_output_satoshis
        return if output_total <= input_total

        raise VerificationError.new(:output_overflow,
                                    "outputs (#{output_total}) exceed inputs (#{input_total}) for transaction #{tx.txid_hex}")
      end

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

      # Collect this transaction and all its ancestors in dependency order
      # (ancestors first, self last). Stops recursion at transactions with
      # a merkle_path (proven leaves). Deduplicates by txid.
      def collect_ancestors
        seen = {}
        result = []
        collect_ancestors_recursive(self, seen, result)
        result
      end

      def collect_ancestors_recursive(tx, seen, result)
        txid = tx.txid
        return if seen.key?(txid)

        unless tx.merkle_path
          tx.inputs.each do |input|
            next unless input.source_transaction

            collect_ancestors_recursive(input.source_transaction, seen, result)
          end
        end

        seen[txid] = true
        result << tx
      end

      def compute_fee_sats(model_or_fee)
        case model_or_fee
        when nil
          FeeModels::SatoshisPerKilobyte.new.compute_fee(self)
        when FeeModel
          model_or_fee.compute_fee(self)
        when Numeric
          model_or_fee.ceil
        else
          raise ArgumentError, "expected FeeModel, Numeric, or nil; got #{model_or_fee.class}"
        end
      end

      def distribute_change(fee_sats, change_distribution)
        change_outputs = @outputs.select(&:change)
        return if change_outputs.empty?

        input_sats = total_input_satoshis
        non_change_sats = @outputs.reject(&:change).sum(&:satoshis)
        available = input_sats - non_change_sats - fee_sats

        if available <= change_outputs.length
          @outputs.reject!(&:change)
          return
        end

        if change_distribution == :random
          distribute_random_change(available, change_outputs)
        else
          distribute_equal_change(available, change_outputs)
        end
      end

      def distribute_equal_change(available, change_outputs)
        per_output = available / change_outputs.length
        remainder = available % change_outputs.length
        change_outputs.each_with_index do |output, i|
          output.satoshis = per_output + (i < remainder ? 1 : 0)
        end
      end

      # Distribute change using a Benford-inspired algorithm that biases amounts
      # towards the lower end of the available range.
      #
      # Algorithm:
      # 1. Reserve 1 satoshi per change output as a minimum guarantee.
      # 2. For each output except the last, take a Benford-scaled portion of the
      #    remaining pool and add it to that output's base amount.
      # 3. The last change output receives only its 1 sat base.
      # 4. Any remainder (from floor rounding) is assigned to the last transaction
      #    output, matching TS SDK behaviour.
      #
      # @param available [Integer] total satoshis to distribute
      # @param change_outputs [Array<TransactionOutput>] outputs flagged as change
      # @return [void]
      def distribute_random_change(available, change_outputs)
        n = change_outputs.length

        # Initialise each output with a 1-sat base and reserve that pool
        amounts = Array.new(n, 1)
        pool = available - n
        distributed = n

        # Allocate Benford-scaled portions to all outputs except the last
        (n - 1).times do |i|
          portion = benford_number(0, pool)
          amounts[i] += portion
          distributed += portion
          pool -= portion
        end

        # Assign computed amounts to change outputs
        change_outputs.each_with_index do |output, i|
          output.satoshis = amounts[i]
        end

        # Assign any remainder (floor-rounding loss) to the last transaction output
        remainder = available - distributed
        return unless remainder.positive?

        last_output = @outputs.last
        last_output.satoshis = (last_output.satoshis || 0) + remainder
      end

      # Generate a Benford-inspired integer in the range [min, max).
      #
      # Randomly selects a scale factor that biases the result towards the lower end of
      # the range, based on the Benford distribution of leading digits.
      #
      # Reference ts SDK implementation
      # Math.floor(min + ((max - min) * Math.log10(1 + 1 / d)) / Math.log10(10))
      #
      # We simplify:
      #  - log10(10) = 1, divide by 1 is a no-op, removed it
      #  - pre-calculated the 9 possible values to a look-up table LOG10_RECIPROCAL_D_VALUES_1TO9
      #  - rearrange to "start at min, add a scaled portion of the range"
      #
      # @param min [Integer] lower bound (inclusive)
      # @param max [Integer] upper bound (exclusive)
      # @return [Integer] Benford-distributed integer
      def benford_number(min, max)
        scale_factor = LOG10_RECIPROCAL_D_VALUES_1TO9[Random.rand(9)] # Array indexing starts at 0
        (min + (scale_factor * (max - min))).floor
      end
    end
  end
end
