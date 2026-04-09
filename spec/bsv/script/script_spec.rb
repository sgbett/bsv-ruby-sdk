# frozen_string_literal: true

RSpec.describe BSV::Script::Script do
  # Known P2PKH locking script for the generator point pubkey
  let(:p2pkh_hash) { ['751e76e8199196d454941c45d1b3a323f1433bd6'].pack('H*') }
  let(:p2pkh_hex) { '76a914751e76e8199196d454941c45d1b3a323f1433bd688ac' }
  let(:p2pkh_asm) { 'OP_DUP OP_HASH160 751e76e8199196d454941c45d1b3a323f1433bd6 OP_EQUALVERIFY OP_CHECKSIG' }

  describe '.from_hex / #to_hex' do
    it 'round-trips hex' do
      script = described_class.from_hex(p2pkh_hex)
      expect(script.to_hex).to eq(p2pkh_hex)
    end
  end

  describe '.from_binary / #to_binary' do
    it 'round-trips binary' do
      binary = [p2pkh_hex].pack('H*')
      script = described_class.from_binary(binary)
      expect(script.to_binary).to eq(binary)
    end
  end

  describe '.from_asm / #to_asm' do
    it 'parses ASM into a script' do
      script = described_class.from_asm(p2pkh_asm)
      expect(script.to_hex).to eq(p2pkh_hex)
    end

    it 'round-trips ASM' do
      script = described_class.from_asm(p2pkh_asm)
      expect(script.to_asm).to eq(p2pkh_asm)
    end
  end

  describe '.from_chunks' do
    it 'builds a script from chunk objects' do
      chunks = [
        BSV::Script::Chunk.new(opcode: BSV::Script::Opcodes::OP_DUP),
        BSV::Script::Chunk.new(opcode: BSV::Script::Opcodes::OP_HASH160),
        BSV::Script::Chunk.new(opcode: 0x14, data: p2pkh_hash),
        BSV::Script::Chunk.new(opcode: BSV::Script::Opcodes::OP_EQUALVERIFY),
        BSV::Script::Chunk.new(opcode: BSV::Script::Opcodes::OP_CHECKSIG)
      ]
      script = described_class.from_chunks(chunks)
      expect(script.to_hex).to eq(p2pkh_hex)
    end
  end

  describe '#chunks' do
    it 'lazily parses a P2PKH script into chunks' do
      script = described_class.from_hex(p2pkh_hex)
      chunks = script.chunks

      expect(chunks.length).to eq(5)
      expect(chunks[0].opcode).to eq(BSV::Script::Opcodes::OP_DUP)
      expect(chunks[1].opcode).to eq(BSV::Script::Opcodes::OP_HASH160)
      expect(chunks[2].data).to eq(p2pkh_hash)
      expect(chunks[3].opcode).to eq(BSV::Script::Opcodes::OP_EQUALVERIFY)
      expect(chunks[4].opcode).to eq(BSV::Script::Opcodes::OP_CHECKSIG)
    end
  end

  describe '#length' do
    it 'returns the byte length of the script' do
      script = described_class.from_hex(p2pkh_hex)
      expect(script.length).to eq(25)
    end
  end

  describe '.op_return' do
    it 'creates an OP_FALSE OP_RETURN script with data' do
      hash = BSV::Primitives::Digest.sha256('hello')
      script = described_class.op_return(hash)

      expect(script.to_binary[0].ord).to eq(BSV::Script::Opcodes::OP_FALSE)
      expect(script.to_binary[1].ord).to eq(BSV::Script::Opcodes::OP_RETURN)
      # 0x20 = push 32 bytes, then 32 bytes of hash
      expect(script.to_binary[2].ord).to eq(0x20)
      expect(script.to_binary[3, 32]).to eq(hash)
      expect(script.length).to eq(35)
    end

    it 'supports multiple data items' do
      data1 = 'hello'.b
      data2 = 'world'.b
      script = described_class.op_return(data1, data2)

      # After F3.1 fix: OP_RETURN at top level absorbs all trailing bytes into its
      # data field. The chunk array is [OP_FALSE, OP_RETURN(raw_tail)].
      chunks = script.chunks
      expect(chunks.length).to eq(2)
      expect(chunks[0].opcode).to eq(BSV::Script::Opcodes::OP_FALSE)
      expect(chunks[1].opcode).to eq(BSV::Script::Opcodes::OP_RETURN)
      expect(chunks[1].data?).to be true

      # op_return_data re-parses the tail and returns individual push payloads
      expect(script.op_return_data).to eq([data1, data2])
    end

    it 'renders correct ASM' do
      # After F3.1 fix: the raw tail bytes (push opcode + data) are the OP_RETURN
      # chunk's data, rendered as hex. For "\xde\xad" the tail is "\x02\xde\xad".
      script = described_class.op_return("\xde\xad".b)
      expect(script.to_asm).to eq('OP_0 OP_RETURN 02dead')
    end
  end

  describe '.p2pkh_lock' do
    it 'creates a standard P2PKH locking script' do
      script = described_class.p2pkh_lock(p2pkh_hash)
      expect(script.to_hex).to eq(p2pkh_hex)
      expect(script.to_asm).to eq(p2pkh_asm)
    end

    it 'raises on invalid hash length' do
      expect { described_class.p2pkh_lock("\x00".b * 19) }
        .to raise_error(ArgumentError, /20 bytes/)
    end
  end

  describe '.p2pkh_unlock' do
    it 'creates an unlocking script with signature and pubkey' do
      # Use real-ish data sizes (DER sig ~71 bytes, compressed pubkey 33 bytes)
      sig = "\x30".b + ("\x01".b * 70)
      pubkey = "\x02".b + ("\xab".b * 32)

      script = described_class.p2pkh_unlock(sig, pubkey)
      chunks = script.chunks

      expect(chunks.length).to eq(2)
      expect(chunks[0].data).to eq(sig)
      expect(chunks[1].data).to eq(pubkey)
    end
  end

  describe '.p2pk_lock / .p2pk_unlock' do
    it 'creates a P2PK locking script with compressed pubkey' do
      pubkey = "\x02".b + ("\xab".b * 32)
      script = described_class.p2pk_lock(pubkey)

      expect(script).to be_p2pk
      chunks = script.chunks
      expect(chunks.length).to eq(2)
      expect(chunks[0].data).to eq(pubkey)
      expect(chunks[1].opcode).to eq(BSV::Script::Opcodes::OP_CHECKSIG)
    end

    it 'creates a P2PK locking script with uncompressed pubkey' do
      pubkey = "\x04".b + ("\xab".b * 64)
      script = described_class.p2pk_lock(pubkey)
      expect(script).to be_p2pk
    end

    it 'raises on invalid pubkey length' do
      expect { described_class.p2pk_lock("\x02".b * 20) }
        .to raise_error(ArgumentError, /33 or 65 bytes/)
    end

    it 'creates a P2PK unlocking script' do
      sig = "\x30".b + ("\x01".b * 70)
      script = described_class.p2pk_unlock(sig)

      chunks = script.chunks
      expect(chunks.length).to eq(1)
      expect(chunks[0].data).to eq(sig)
    end
  end

  describe '.p2ms_lock / .p2ms_unlock' do
    let(:alice_key) { "\x02".b + ("\x11".b * 32) }
    let(:bob_key) { "\x03".b + ("\x22".b * 32) }
    let(:carol_key) { "\x02".b + ("\x33".b * 32) }

    it 'creates a 2-of-3 multisig locking script' do
      script = described_class.p2ms_lock(2, [alice_key, bob_key, carol_key])

      expect(script).to be_multisig
      chunks = script.chunks
      expect(chunks.length).to eq(6) # OP_2 alice bob carol OP_3 OP_CHECKMULTISIG
    end

    it 'produces correct opcodes and data for 2-of-3' do
      script = described_class.p2ms_lock(2, [alice_key, bob_key, carol_key])
      chunks = script.chunks

      expect(chunks[0].opcode).to eq(BSV::Script::Opcodes::OP_2)
      expect(chunks[1].data).to eq(alice_key)
      expect(chunks[2].data).to eq(bob_key)
      expect(chunks[3].data).to eq(carol_key)
      expect(chunks[4].opcode).to eq(BSV::Script::Opcodes::OP_3)
      expect(chunks[5].opcode).to eq(BSV::Script::Opcodes::OP_CHECKMULTISIG)
    end

    it 'creates a 1-of-1 multisig (edge case)' do
      script = described_class.p2ms_lock(1, [alice_key])

      expect(script).to be_multisig
      chunks = script.chunks
      expect(chunks[0].opcode).to eq(BSV::Script::Opcodes::OP_1)
      expect(chunks[-2].opcode).to eq(BSV::Script::Opcodes::OP_1)
      expect(chunks[-1].opcode).to eq(BSV::Script::Opcodes::OP_CHECKMULTISIG)
    end

    it 'raises when m > n' do
      expect { described_class.p2ms_lock(3, [alice_key, bob_key]) }
        .to raise_error(ArgumentError, /m must be between 1 and n/)
    end

    it 'raises when m is 0' do
      expect { described_class.p2ms_lock(0, [alice_key]) }
        .to raise_error(ArgumentError, /m must be between 1 and n/)
    end

    it 'raises when n > 16' do
      keys = 17.times.map { "\x02".b + ("\xaa".b * 32) }
      expect { described_class.p2ms_lock(1, keys) }
        .to raise_error(ArgumentError, /n must be <= 16/)
    end

    it 'creates a multisig unlocking script with OP_0 prefix' do
      sig1 = "\x30".b + ("\x01".b * 70)
      sig2 = "\x30".b + ("\x02".b * 70)
      script = described_class.p2ms_unlock(sig1, sig2)

      chunks = script.chunks
      expect(chunks.length).to eq(3)
      expect(chunks[0].opcode).to eq(BSV::Script::Opcodes::OP_0)
      expect(chunks[0].data).to be_nil
      expect(chunks[1].data).to eq(sig1)
      expect(chunks[2].data).to eq(sig2)
    end
  end

  describe 'push data encoding' do
    it 'uses direct push for data <= 75 bytes' do
      data = 'x'.b * 75
      script = described_class.op_return(data)
      # OP_FALSE(1) + OP_RETURN(1) + push_op(1) + data(75) = 78
      expect(script.length).to eq(78)
    end

    it 'uses OP_PUSHDATA1 for data 76-255 bytes' do
      data = 'x'.b * 100
      script = described_class.op_return(data)
      # OP_FALSE(1) + OP_RETURN(1) + OP_PUSHDATA1(1) + len(1) + data(100) = 104
      expect(script.length).to eq(104)
      expect(script.to_binary[2].ord).to eq(BSV::Script::Opcodes::OP_PUSHDATA1)
    end

    it 'uses OP_PUSHDATA2 for data 256-65535 bytes' do
      data = 'x'.b * 300
      script = described_class.op_return(data)
      # OP_FALSE(1) + OP_RETURN(1) + OP_PUSHDATA2(1) + len(2) + data(300) = 305
      expect(script.length).to eq(305)
      expect(script.to_binary[2].ord).to eq(BSV::Script::Opcodes::OP_PUSHDATA2)
    end
  end

  describe 'type predicates' do
    let(:p2pkh_script) { described_class.p2pkh_lock(p2pkh_hash) }
    let(:op_return_script) { described_class.op_return('hello'.b) }

    describe '#p2pkh?' do
      it 'returns true for a P2PKH locking script' do
        expect(p2pkh_script).to be_p2pkh
      end

      it 'returns false for non-P2PKH scripts' do
        expect(op_return_script).not_to be_p2pkh
      end
    end

    describe '#p2sh?' do
      it 'returns true for a P2SH script' do
        script_hash = "\x9d\xe5\xae\xaf\xf9\xc4\x84\x31\xba\x4d\xd6\xe8\xaf\x73\xd5\x1f\x38\xe4\x51\xcb".b
        script = described_class.builder
                                .push_op(:OP_HASH160)
                                .push_data(script_hash)
                                .push_op(:OP_EQUAL)
                                .build
        expect(script).to be_p2sh
      end

      it 'returns false for P2PKH' do
        expect(p2pkh_script).not_to be_p2sh
      end
    end

    describe '#op_return?' do
      it 'detects OP_FALSE OP_RETURN format' do
        expect(op_return_script).to be_op_return
      end

      it 'detects bare OP_RETURN format' do
        script = described_class.from_binary([BSV::Script::Opcodes::OP_RETURN].pack('C'))
        expect(script).to be_op_return
      end

      it 'returns false for P2PKH' do
        expect(p2pkh_script).not_to be_op_return
      end
    end

    describe '#p2pk?' do
      it 'returns true for compressed pubkey + OP_CHECKSIG' do
        pubkey = "\x02".b + ("\xab".b * 32)
        script = described_class.builder
                                .push_data(pubkey)
                                .push_op(:OP_CHECKSIG)
                                .build
        expect(script).to be_p2pk
      end

      it 'returns true for uncompressed pubkey + OP_CHECKSIG' do
        pubkey = "\x04".b + ("\xab".b * 64)
        script = described_class.builder
                                .push_data(pubkey)
                                .push_op(:OP_CHECKSIG)
                                .build
        expect(script).to be_p2pk
      end

      it 'returns false for P2PKH' do
        expect(p2pkh_script).not_to be_p2pk
      end
    end

    describe '#multisig?' do
      it 'returns true for a 2-of-3 multisig script' do
        key1 = "\x02".b + ("\x11".b * 32)
        key2 = "\x03".b + ("\x22".b * 32)
        key3 = "\x02".b + ("\x33".b * 32)
        script = described_class.builder
                                .push_op(:OP_2)
                                .push_data(key1)
                                .push_data(key2)
                                .push_data(key3)
                                .push_op(:OP_3)
                                .push_op(:OP_CHECKMULTISIG)
                                .build
        expect(script).to be_multisig
      end

      it 'returns false for P2PKH' do
        expect(p2pkh_script).not_to be_multisig
      end
    end
  end

  describe '#type' do
    it 'returns "pubkeyhash" for P2PKH' do
      expect(described_class.p2pkh_lock(p2pkh_hash).type).to eq('pubkeyhash')
    end

    it 'returns "pubkey" for P2PK' do
      pubkey = "\x02".b + ("\xab".b * 32)
      script = described_class.builder.push_data(pubkey).push_op(:OP_CHECKSIG).build
      expect(script.type).to eq('pubkey')
    end

    it 'returns "scripthash" for P2SH' do
      script = described_class.builder
                              .push_op(:OP_HASH160)
                              .push_data("\x00".b * 20)
                              .push_op(:OP_EQUAL)
                              .build
      expect(script.type).to eq('scripthash')
    end

    it 'returns "nulldata" for OP_RETURN' do
      expect(described_class.op_return('data'.b).type).to eq('nulldata')
    end

    it 'returns "multisig" for multisig' do
      key = "\x02".b + ("\x11".b * 32)
      script = described_class.builder
                              .push_op(:OP_1)
                              .push_data(key)
                              .push_op(:OP_1)
                              .push_op(:OP_CHECKMULTISIG)
                              .build
      expect(script.type).to eq('multisig')
    end

    it 'returns "empty" for empty script' do
      expect(described_class.new.type).to eq('empty')
    end

    it 'returns "nonstandard" for unknown scripts' do
      script = described_class.builder.push_op(:OP_DUP).push_op(:OP_DROP).build
      expect(script.type).to eq('nonstandard')
    end
  end

  describe 'data extraction' do
    describe '#pubkey_hash' do
      it 'extracts 20-byte hash from P2PKH' do
        script = described_class.p2pkh_lock(p2pkh_hash)
        expect(script.pubkey_hash).to eq(p2pkh_hash)
      end

      it 'returns nil for non-P2PKH' do
        expect(described_class.op_return('data'.b).pubkey_hash).to be_nil
      end
    end

    describe '#script_hash' do
      it 'extracts 20-byte hash from P2SH' do
        hash = "\x9d\xe5\xae\xaf\xf9\xc4\x84\x31\xba\x4d\xd6\xe8\xaf\x73\xd5\x1f\x38\xe4\x51\xcb".b
        script = described_class.builder
                                .push_op(:OP_HASH160)
                                .push_data(hash)
                                .push_op(:OP_EQUAL)
                                .build
        expect(script.script_hash).to eq(hash)
      end

      it 'returns nil for non-P2SH' do
        expect(described_class.p2pkh_lock(p2pkh_hash).script_hash).to be_nil
      end
    end

    describe '#op_return_data' do
      it 'extracts data items from OP_RETURN' do
        data1 = 'hello'.b
        data2 = 'world'.b
        script = described_class.op_return(data1, data2)
        expect(script.op_return_data).to eq([data1, data2])
      end

      it 'returns nil for non-OP_RETURN' do
        expect(described_class.p2pkh_lock(p2pkh_hash).op_return_data).to be_nil
      end
    end

    describe '#addresses' do
      it 'extracts mainnet address from P2PKH' do
        key = BSV::Primitives::PrivateKey.generate
        hash = key.public_key.hash160
        script = described_class.p2pkh_lock(hash)

        addresses = script.addresses
        expect(addresses.length).to eq(1)
        expect(addresses[0]).to eq(key.public_key.address)
      end

      it 'extracts testnet address from P2PKH' do
        key = BSV::Primitives::PrivateKey.generate
        hash = key.public_key.hash160
        script = described_class.p2pkh_lock(hash)

        addresses = script.addresses(network: :testnet)
        expect(addresses.length).to eq(1)
        expect(addresses[0]).to eq(key.public_key.address(network: :testnet))
      end

      it 'returns empty array for P2SH (no address encoding)' do
        hash = "\x00".b * 20
        script = described_class.builder
                                .push_op(:OP_HASH160)
                                .push_data(hash)
                                .push_op(:OP_EQUAL)
                                .build
        expect(script.addresses).to eq([])
      end

      it 'returns empty array for unknown types' do
        script = described_class.builder.push_op(:OP_DUP).build
        expect(script.addresses).to eq([])
      end
    end
  end

  describe '.pushdrop_lock / .pushdrop_unlock' do
    let(:lock_script) { described_class.p2pkh_lock(p2pkh_hash) }

    # The default lock_position is now :before (lock first, then fields+drops),
    # matching the ts-sdk convention. The structural tests below use
    # lock_position: :after explicitly to preserve their index-based assertions.

    context 'with lock_position: :after (fields first, lock last)' do
      it 'creates a PushDrop script with a single field' do
        field = 'hello'.b
        script = described_class.pushdrop_lock([field], lock_script, lock_position: :after)

        chunks = script.chunks
        # field + OP_DROP + 5 P2PKH chunks = 7
        expect(chunks.length).to eq(7)
        expect(chunks[0].data).to eq(field)
        expect(chunks[1].opcode).to eq(BSV::Script::Opcodes::OP_DROP)
        expect(chunks[2].opcode).to eq(BSV::Script::Opcodes::OP_DUP)
      end

      it 'creates a PushDrop script with two fields (one OP_2DROP)' do
        fields = ['field1'.b, 'field2'.b]
        script = described_class.pushdrop_lock(fields, lock_script, lock_position: :after)

        chunks = script.chunks
        # 2 fields + OP_2DROP + 5 P2PKH chunks = 8
        expect(chunks.length).to eq(8)
        expect(chunks[0].data).to eq('field1'.b)
        expect(chunks[1].data).to eq('field2'.b)
        expect(chunks[2].opcode).to eq(BSV::Script::Opcodes::OP_2DROP)
      end

      it 'creates a PushDrop script with three fields (OP_2DROP + OP_DROP)' do
        fields = ['a'.b, 'b'.b, 'c'.b]
        script = described_class.pushdrop_lock(fields, lock_script, lock_position: :after)

        chunks = script.chunks
        # 3 fields + OP_2DROP + OP_DROP + 5 P2PKH chunks = 10
        expect(chunks.length).to eq(10)
        expect(chunks[3].opcode).to eq(BSV::Script::Opcodes::OP_2DROP)
        expect(chunks[4].opcode).to eq(BSV::Script::Opcodes::OP_DROP)
      end

      it 'creates a PushDrop script with four fields (two OP_2DROPs)' do
        fields = ['a'.b, 'b'.b, 'c'.b, 'd'.b]
        script = described_class.pushdrop_lock(fields, lock_script, lock_position: :after)

        chunks = script.chunks
        # 4 fields + 2*OP_2DROP + 5 P2PKH chunks = 11
        expect(chunks.length).to eq(11)
        expect(chunks[4].opcode).to eq(BSV::Script::Opcodes::OP_2DROP)
        expect(chunks[5].opcode).to eq(BSV::Script::Opcodes::OP_2DROP)
      end

      it 'encodes empty data as OP_0' do
        script = described_class.pushdrop_lock([''.b], lock_script, lock_position: :after)

        chunks = script.chunks
        expect(chunks[0].opcode).to eq(BSV::Script::Opcodes::OP_0)
        expect(chunks[0].data).to be_nil
      end

      it 'encodes single-byte values 1-16 as OP_N' do
        script = described_class.pushdrop_lock(["\x05".b], lock_script, lock_position: :after)

        chunks = script.chunks
        expect(chunks[0].opcode).to eq(BSV::Script::Opcodes::OP_5)
        expect(chunks[0].data).to be_nil
      end

      it 'encodes single zero byte as a direct 1-byte push (not OP_0)' do
        # F3.14/F3.21: [0x00] must NOT collapse to OP_0 — semantically different.
        # OP_0 pushes an empty array; [0x00] pushes a one-byte zero.
        script = described_class.pushdrop_lock(["\x00".b], lock_script, lock_position: :after)

        chunks = script.chunks
        expect(chunks[0].opcode).to eq(1) # direct 1-byte push
        expect(chunks[0].data).to eq("\x00".b)
      end

      it 'encodes 0x81 as OP_1NEGATE' do
        script = described_class.pushdrop_lock(["\x81".b], lock_script, lock_position: :after)

        chunks = script.chunks
        expect(chunks[0].opcode).to eq(BSV::Script::Opcodes::OP_1NEGATE)
      end

      it 'handles large data fields with OP_PUSHDATA1' do
        large_field = "\xff".b * 200
        script = described_class.pushdrop_lock([large_field], lock_script, lock_position: :after)

        chunks = script.chunks
        expect(chunks[0].opcode).to eq(BSV::Script::Opcodes::OP_PUSHDATA1)
        expect(chunks[0].data).to eq(large_field)
      end

      it 'handles large data fields with OP_PUSHDATA2' do
        large_field = "\xff".b * 400
        script = described_class.pushdrop_lock([large_field], lock_script, lock_position: :after)

        chunks = script.chunks
        expect(chunks[0].opcode).to eq(BSV::Script::Opcodes::OP_PUSHDATA2)
        expect(chunks[0].data).to eq(large_field)
      end

      it 'round-trips through binary serialisation' do
        fields = ['token_id'.b, 'metadata'.b, "\x42".b]
        script = described_class.pushdrop_lock(fields, lock_script, lock_position: :after)

        parsed = described_class.from_binary(script.to_binary)
        expect(parsed.to_hex).to eq(script.to_hex)
        expect(parsed).to be_pushdrop
      end
    end

    context 'with lock_position: :before (default — lock first, then fields+drops)' do
      it 'places the lock script before the fields' do
        field = 'hello'.b
        script = described_class.pushdrop_lock([field], lock_script)

        chunks = script.chunks
        # 5 P2PKH chunks + field + OP_DROP = 7
        expect(chunks.length).to eq(7)
        expect(chunks[0].opcode).to eq(BSV::Script::Opcodes::OP_DUP)
        expect(chunks[4].opcode).to eq(BSV::Script::Opcodes::OP_CHECKSIG)
        expect(chunks[5].data).to eq(field)
        expect(chunks[6].opcode).to eq(BSV::Script::Opcodes::OP_DROP)
      end

      it 'places the lock script before multiple fields' do
        fields = ['field1'.b, 'field2'.b]
        script = described_class.pushdrop_lock(fields, lock_script)

        chunks = script.chunks
        # 5 P2PKH chunks + 2 fields + OP_2DROP = 8
        expect(chunks.length).to eq(8)
        expect(chunks[0].opcode).to eq(BSV::Script::Opcodes::OP_DUP)
        expect(chunks[5].data).to eq('field1'.b)
        expect(chunks[6].data).to eq('field2'.b)
        expect(chunks[7].opcode).to eq(BSV::Script::Opcodes::OP_2DROP)
      end

      it 'is detected as pushdrop?' do
        script = described_class.pushdrop_lock(['data'.b], lock_script)
        expect(script).to be_pushdrop
      end

      it 'round-trips through binary serialisation' do
        fields = ['token_id'.b, 'metadata'.b]
        script = described_class.pushdrop_lock(fields, lock_script)

        parsed = described_class.from_binary(script.to_binary)
        expect(parsed.to_hex).to eq(script.to_hex)
        expect(parsed).to be_pushdrop
      end

      it 'extracts fields correctly via pushdrop_fields' do
        fields = ['hello'.b, 'world'.b]
        script = described_class.pushdrop_lock(fields, lock_script)
        expect(script.pushdrop_fields).to eq(fields)
      end

      it 'extracts the lock script correctly via pushdrop_lock_script' do
        fields = ['hello'.b]
        script = described_class.pushdrop_lock(fields, lock_script)
        expect(script.pushdrop_lock_script.to_hex).to eq(lock_script.to_hex)
      end
    end

    it 'raises on empty fields array' do
      expect { described_class.pushdrop_lock([], lock_script) }
        .to raise_error(ArgumentError, /fields must not be empty/)
    end

    it 'raises when lock_script is not a Script' do
      expect { described_class.pushdrop_lock(['data'.b], 'not a script') }
        .to raise_error(ArgumentError, /lock_script must be a Script/)
    end

    it 'raises when lock_position is invalid' do
      expect { described_class.pushdrop_lock(['data'.b], lock_script, lock_position: :sideways) }
        .to raise_error(ArgumentError, /lock_position must be :before or :after/)
    end

    it 'returns the unlock_script unchanged from pushdrop_unlock' do
      unlock = described_class.p2pkh_unlock("\x30".b + ("\x01".b * 70), "\x02".b + ("\xab".b * 32))
      result = described_class.pushdrop_unlock(unlock)
      expect(result).to equal(unlock)
    end
  end

  describe '#pushdrop?' do
    let(:lock_script) { described_class.p2pkh_lock(p2pkh_hash) }

    it 'returns true for a PushDrop script' do
      script = described_class.pushdrop_lock(['data'.b], lock_script)
      expect(script).to be_pushdrop
    end

    it 'returns true for multi-field PushDrop' do
      script = described_class.pushdrop_lock(['a'.b, 'b'.b, 'c'.b, 'd'.b, 'e'.b], lock_script)
      expect(script).to be_pushdrop
    end

    it 'returns false for P2PKH' do
      expect(lock_script).not_to be_pushdrop
    end

    it 'returns false for OP_RETURN' do
      expect(described_class.op_return('data'.b)).not_to be_pushdrop
    end

    it 'returns true when fields are minimally encoded as OP_N' do
      script = described_class.pushdrop_lock(["\x05".b], lock_script)
      expect(script).to be_pushdrop
    end

    it 'returns true when field is OP_1NEGATE' do
      script = described_class.pushdrop_lock(["\x81".b], lock_script)
      expect(script).to be_pushdrop
    end

    it 'returns false for empty script' do
      expect(described_class.new).not_to be_pushdrop
    end
  end

  describe '#pushdrop_fields' do
    let(:lock_script) { described_class.p2pkh_lock(p2pkh_hash) }

    it 'extracts fields from a PushDrop script' do
      fields = ['token_id'.b, 'metadata'.b]
      script = described_class.pushdrop_lock(fields, lock_script)

      expect(script.pushdrop_fields).to eq(fields)
    end

    it 'returns empty binary for OP_0-encoded fields' do
      script = described_class.pushdrop_lock([''.b], lock_script)

      extracted = script.pushdrop_fields
      expect(extracted.length).to eq(1)
      expect(extracted[0]).to eq(''.b)
    end

    it 'round-trips minimally-encoded OP_N fields' do
      fields = ["\x05".b, "\x10".b, "\x01".b]
      script = described_class.pushdrop_lock(fields, lock_script)

      expect(script.pushdrop_fields).to eq(fields)
    end

    it 'round-trips OP_1NEGATE field' do
      fields = ["\x81".b]
      script = described_class.pushdrop_lock(fields, lock_script)

      expect(script.pushdrop_fields).to eq(fields)
    end

    it 'returns nil for non-PushDrop scripts' do
      expect(described_class.p2pkh_lock(p2pkh_hash).pushdrop_fields).to be_nil
    end
  end

  describe '#pushdrop_lock_script' do
    let(:lock_script) { described_class.p2pkh_lock(p2pkh_hash) }

    it 'extracts the underlying lock script' do
      script = described_class.pushdrop_lock(['data'.b], lock_script)

      extracted = script.pushdrop_lock_script
      expect(extracted.to_hex).to eq(lock_script.to_hex)
      expect(extracted).to be_p2pkh
    end

    it 'returns nil for non-PushDrop scripts' do
      expect(lock_script.pushdrop_lock_script).to be_nil
    end
  end

  describe '#type (pushdrop)' do
    it 'returns "pushdrop" for PushDrop scripts' do
      lock_script = described_class.p2pkh_lock(p2pkh_hash)
      script = described_class.pushdrop_lock(['data'.b], lock_script)
      expect(script.type).to eq('pushdrop')
    end
  end

  describe '.rpuzzle_lock / .rpuzzle_unlock' do
    let(:hash160_value) { "\xab".b * 20 }
    let(:sha256_value) { "\xcd".b * 32 }
    let(:raw_r_value) { "\xef".b * 32 }

    let(:prefix_opcodes) do
      [
        BSV::Script::Opcodes::OP_OVER, BSV::Script::Opcodes::OP_3,
        BSV::Script::Opcodes::OP_SPLIT, BSV::Script::Opcodes::OP_NIP,
        BSV::Script::Opcodes::OP_1, BSV::Script::Opcodes::OP_SPLIT,
        BSV::Script::Opcodes::OP_SWAP, BSV::Script::Opcodes::OP_SPLIT,
        BSV::Script::Opcodes::OP_DROP
      ]
    end

    it 'creates a hash160 RPuzzle lock (default)' do
      script = described_class.rpuzzle_lock(hash160_value)

      chunks = script.chunks
      # 9 prefix + OP_HASH160 + hash + OP_EQUALVERIFY + OP_CHECKSIG = 13
      expect(chunks.length).to eq(13)
      prefix_opcodes.each_with_index do |op, i|
        expect(chunks[i].opcode).to eq(op)
      end
      expect(chunks[9].opcode).to eq(BSV::Script::Opcodes::OP_HASH160)
      expect(chunks[10].data).to eq(hash160_value)
      expect(chunks[11].opcode).to eq(BSV::Script::Opcodes::OP_EQUALVERIFY)
      expect(chunks[12].opcode).to eq(BSV::Script::Opcodes::OP_CHECKSIG)
    end

    it 'creates a sha256 RPuzzle lock' do
      script = described_class.rpuzzle_lock(sha256_value, hash_type: :sha256)

      chunks = script.chunks
      expect(chunks.length).to eq(13)
      expect(chunks[9].opcode).to eq(BSV::Script::Opcodes::OP_SHA256)
      expect(chunks[10].data).to eq(sha256_value)
    end

    it 'creates a ripemd160 RPuzzle lock' do
      hash = "\xbb".b * 20
      script = described_class.rpuzzle_lock(hash, hash_type: :ripemd160)

      chunks = script.chunks
      expect(chunks[9].opcode).to eq(BSV::Script::Opcodes::OP_RIPEMD160)
      expect(chunks[10].data).to eq(hash)
    end

    it 'creates a sha1 RPuzzle lock' do
      hash = "\xcc".b * 20
      script = described_class.rpuzzle_lock(hash, hash_type: :sha1)

      chunks = script.chunks
      expect(chunks[9].opcode).to eq(BSV::Script::Opcodes::OP_SHA1)
      expect(chunks[10].data).to eq(hash)
    end

    it 'creates a hash256 RPuzzle lock' do
      hash = "\xdd".b * 32
      script = described_class.rpuzzle_lock(hash, hash_type: :hash256)

      chunks = script.chunks
      expect(chunks[9].opcode).to eq(BSV::Script::Opcodes::OP_HASH256)
      expect(chunks[10].data).to eq(hash)
    end

    it 'creates a raw RPuzzle lock (no hash op)' do
      script = described_class.rpuzzle_lock(raw_r_value, hash_type: :raw)

      chunks = script.chunks
      # 9 prefix + r_value + OP_EQUALVERIFY + OP_CHECKSIG = 12 (no hash op)
      expect(chunks.length).to eq(12)
      expect(chunks[9].data).to eq(raw_r_value)
      expect(chunks[10].opcode).to eq(BSV::Script::Opcodes::OP_EQUALVERIFY)
      expect(chunks[11].opcode).to eq(BSV::Script::Opcodes::OP_CHECKSIG)
    end

    it 'raises on unknown hash type' do
      expect { described_class.rpuzzle_lock("\x00".b * 20, hash_type: :md5) }
        .to raise_error(ArgumentError, /unknown hash_type/)
    end

    it 'round-trips through binary serialisation' do
      script = described_class.rpuzzle_lock(hash160_value)

      parsed = described_class.from_binary(script.to_binary)
      expect(parsed.to_hex).to eq(script.to_hex)
      expect(parsed).to be_rpuzzle
    end

    it 'creates an RPuzzle unlock script (same as P2PKH)' do
      sig = "\x30".b + ("\x01".b * 70)
      pubkey = "\x02".b + ("\xab".b * 32)
      script = described_class.rpuzzle_unlock(sig, pubkey)

      chunks = script.chunks
      expect(chunks.length).to eq(2)
      expect(chunks[0].data).to eq(sig)
      expect(chunks[1].data).to eq(pubkey)
    end
  end

  describe '#rpuzzle?' do
    it 'returns true for a hash160 RPuzzle' do
      script = described_class.rpuzzle_lock("\xab".b * 20)
      expect(script).to be_rpuzzle
    end

    it 'returns true for a raw RPuzzle' do
      script = described_class.rpuzzle_lock("\xef".b * 32, hash_type: :raw)
      expect(script).to be_rpuzzle
    end

    it 'returns true for all hash type variants' do
      %i[sha1 sha256 ripemd160 hash160 hash256].each do |ht|
        script = described_class.rpuzzle_lock("\xab".b * 20, hash_type: ht)
        expect(script).to be_rpuzzle
      end
    end

    it 'returns false for P2PKH' do
      expect(described_class.p2pkh_lock(p2pkh_hash)).not_to be_rpuzzle
    end

    it 'returns false for OP_RETURN' do
      expect(described_class.op_return('data'.b)).not_to be_rpuzzle
    end

    it 'returns false for empty script' do
      expect(described_class.new).not_to be_rpuzzle
    end
  end

  describe '#rpuzzle_hash' do
    it 'extracts the hash from a hash160 RPuzzle' do
      hash = "\xab".b * 20
      script = described_class.rpuzzle_lock(hash)
      expect(script.rpuzzle_hash).to eq(hash)
    end

    it 'extracts the R-value from a raw RPuzzle' do
      r_value = "\xef".b * 32
      script = described_class.rpuzzle_lock(r_value, hash_type: :raw)
      expect(script.rpuzzle_hash).to eq(r_value)
    end

    it 'returns nil for non-RPuzzle scripts' do
      expect(described_class.p2pkh_lock(p2pkh_hash).rpuzzle_hash).to be_nil
    end
  end

  describe '#rpuzzle_hash_type' do
    it 'returns :hash160 for default RPuzzle' do
      script = described_class.rpuzzle_lock("\xab".b * 20)
      expect(script.rpuzzle_hash_type).to eq(:hash160)
    end

    it 'returns :raw for raw RPuzzle' do
      script = described_class.rpuzzle_lock("\xef".b * 32, hash_type: :raw)
      expect(script.rpuzzle_hash_type).to eq(:raw)
    end

    it 'returns correct type for each variant' do
      %i[sha1 sha256 ripemd160 hash160 hash256].each do |ht|
        script = described_class.rpuzzle_lock("\xab".b * 20, hash_type: ht)
        expect(script.rpuzzle_hash_type).to eq(ht)
      end
    end

    it 'returns nil for non-RPuzzle scripts' do
      expect(described_class.p2pkh_lock(p2pkh_hash).rpuzzle_hash_type).to be_nil
    end
  end

  describe '#type (rpuzzle)' do
    it 'returns "rpuzzle" for RPuzzle scripts' do
      script = described_class.rpuzzle_lock("\xab".b * 20)
      expect(script.type).to eq('rpuzzle')
    end

    it 'returns "rpuzzle" for raw RPuzzle scripts' do
      script = described_class.rpuzzle_lock("\xef".b * 32, hash_type: :raw)
      expect(script.type).to eq('rpuzzle')
    end
  end

  describe '#==' do
    it 'considers scripts with identical bytes equal' do
      a = described_class.from_hex(p2pkh_hex)
      b = described_class.from_hex(p2pkh_hex)
      expect(a).to eq(b)
    end

    it 'considers different scripts unequal' do
      a = described_class.op_return('hello'.b)
      b = described_class.op_return('world'.b)
      expect(a).not_to eq(b)
    end
  end

  # F3.16: truncated scripts are parsed leniently — a partial chunk array is
  # returned instead of raising. The final chunk contains whatever bytes
  # remained at the truncation point.
  describe 'truncated script parsing' do
    it 'returns partial chunks for a truncated direct push (missing data bytes)' do
      script = described_class.new("\x05".b) # says "push 5 bytes" but only 0 follow
      chunks = script.chunks
      expect(chunks.length).to eq(1)
      expect(chunks[0].opcode).to eq(5)
      expect(chunks[0].data).to eq(''.b) # zero available bytes
    end

    it 'returns partial chunks for OP_PUSHDATA1 with missing length byte' do
      script = described_class.new("\x4c".b)
      chunks = script.chunks
      expect(chunks.length).to eq(1)
      expect(chunks[0].opcode).to eq(BSV::Script::Opcodes::OP_PUSHDATA1)
      expect(chunks[0].data).to eq(''.b)
    end

    it 'returns partial chunks for OP_PUSHDATA2 with missing length bytes' do
      script = described_class.new("\x4d".b)
      chunks = script.chunks
      expect(chunks.length).to eq(1)
      expect(chunks[0].opcode).to eq(BSV::Script::Opcodes::OP_PUSHDATA2)
    end

    it 'returns partial chunks for OP_PUSHDATA2 with partial length' do
      script = described_class.new("\x4d\x01".b)
      chunks = script.chunks
      expect(chunks.length).to eq(1)
      expect(chunks[0].opcode).to eq(BSV::Script::Opcodes::OP_PUSHDATA2)
    end

    it 'returns partial chunks for OP_PUSHDATA4 with missing length bytes' do
      script = described_class.new("\x4e".b)
      chunks = script.chunks
      expect(chunks.length).to eq(1)
      expect(chunks[0].opcode).to eq(BSV::Script::Opcodes::OP_PUSHDATA4)
    end

    it 'returns partial chunks for OP_PUSHDATA4 with partial length' do
      script = described_class.new("\x4e\x01\x00".b)
      chunks = script.chunks
      expect(chunks.length).to eq(1)
      expect(chunks[0].opcode).to eq(BSV::Script::Opcodes::OP_PUSHDATA4)
    end

    it 'does not match any standard type for a truncated script' do
      script = described_class.new("\x05".b)
      expect(script).not_to be_p2pkh
      expect(script).not_to be_op_return
    end

    it 'parses a valid OP_PUSHDATA1 script correctly' do
      script = described_class.new("\x4c\x03abc".b)
      expect(script.chunks.length).to eq(1)
      expect(script.chunks[0].data).to eq('abc'.b)
    end
  end
end
