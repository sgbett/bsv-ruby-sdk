# frozen_string_literal: true

module BSV
  module Transaction
    class Transaction
      UNSIGNED_P2PKH_INPUT_SIZE = 148

      attr_reader :version, :lock_time, :inputs, :outputs
      attr_accessor :merkle_path

      def initialize(version: 1, lock_time: 0)
        @version = version
        @lock_time = lock_time
        @inputs = []
        @outputs = []
        @merkle_path = nil
      end

      def add_input(input)
        @inputs << input
        self
      end

      def add_output(output)
        @outputs << output
        self
      end

      # --- Serialisation ---

      def to_binary
        buf = [@version].pack('V')
        buf << VarInt.encode(@inputs.length)
        @inputs.each { |i| buf << i.to_binary }
        buf << VarInt.encode(@outputs.length)
        @outputs.each { |o| buf << o.to_binary }
        buf << [@lock_time].pack('V')
        buf
      end

      def to_hex
        to_binary.unpack1('H*')
      end

      def self.from_binary(data)
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

        tx.instance_variable_set(:@lock_time, data.byteslice(offset, 4).unpack1('V'))
        tx
      end

      def self.from_hex(hex)
        from_binary([hex].pack('H*'))
      end

      def self.from_binary_with_offset(data, offset = 0)
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

        tx.instance_variable_set(:@lock_time, data.byteslice(offset, 4).unpack1('V'))
        offset += 4

        [tx, offset - start]
      end

      # --- Transaction ID ---

      def txid
        BSV::Primitives::Digest.sha256d(to_binary).reverse
      end

      def txid_hex
        txid.unpack1('H*')
      end

      # --- Sighash (BIP-143 with FORKID) ---

      def sighash_preimage(input_index, sighash_type = Sighash::ALL_FORK_ID)
        raise ArgumentError, 'only SIGHASH_FORKID types are supported' unless sighash_type & Sighash::FORK_ID != 0

        input = @inputs[input_index]

        # 1. nVersion (4 LE)
        buf = [@version].pack('V')

        # 2. hashPrevouts — SHA256d of all outpoints
        buf << hash_prevouts

        # 3. hashSequence — SHA256d of all sequences
        buf << hash_sequence

        # 4. outpoint of this input (32 + 4)
        buf << input.outpoint_binary

        # 5. scriptCode of this input (varint + script)
        script_bytes = input.source_locking_script.to_binary
        buf << VarInt.encode(script_bytes.bytesize)
        buf << script_bytes

        # 6. value of this input (8 LE)
        buf << [input.source_satoshis].pack('Q<')

        # 7. nSequence of this input (4 LE)
        buf << [input.sequence].pack('V')

        # 8. hashOutputs — SHA256d of all outputs
        buf << hash_outputs

        # 9. nLockTime (4 LE)
        buf << [@lock_time].pack('V')

        # 10. sighash type (4 LE) — includes FORKID flag
        buf << [sighash_type].pack('V')

        buf
      end

      def sighash(input_index, sighash_type = Sighash::ALL_FORK_ID)
        BSV::Primitives::Digest.sha256d(sighash_preimage(input_index, sighash_type))
      end

      # --- Signing ---

      def sign(input_index, private_key, sighash_type = Sighash::ALL_FORK_ID)
        hash = sighash(input_index, sighash_type)
        signature = private_key.sign(hash)
        sig_with_hashtype = signature.to_der + [sighash_type].pack('C')
        pubkey_bytes = private_key.public_key.compressed

        @inputs[input_index].unlocking_script =
          BSV::Script::Script.p2pkh_unlock(sig_with_hashtype, pubkey_bytes)
        self
      end

      def sign_all(private_key, sighash_type = Sighash::ALL_FORK_ID)
        @inputs.each_with_index do |input, index|
          sign(index, private_key, sighash_type) unless input.unlocking_script
        end
        self
      end

      # --- Fee estimation ---

      def total_input_satoshis
        @inputs.sum { |i| i.source_satoshis || 0 }
      end

      def total_output_satoshis
        @outputs.sum(&:satoshis)
      end

      def estimated_fee(satoshis_per_byte: 0.5)
        size = estimated_size
        (size * satoshis_per_byte).ceil
      end

      private

      def hash_prevouts
        buf = @inputs.map(&:outpoint_binary).join
        BSV::Primitives::Digest.sha256d(buf)
      end

      def hash_sequence
        buf = @inputs.map { |i| [i.sequence].pack('V') }.join
        BSV::Primitives::Digest.sha256d(buf)
      end

      def hash_outputs
        buf = @outputs.map(&:to_binary).join
        BSV::Primitives::Digest.sha256d(buf)
      end

      def estimated_size
        size = 4 # version
        size += VarInt.encode(@inputs.length).bytesize
        @inputs.each do |input|
          size += if input.unlocking_script
                    input.to_binary.bytesize
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
