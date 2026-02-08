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

      chunks = script.chunks
      expect(chunks.length).to eq(4) # OP_FALSE, OP_RETURN, data1, data2
      expect(chunks[0].opcode).to eq(BSV::Script::Opcodes::OP_FALSE)
      expect(chunks[1].opcode).to eq(BSV::Script::Opcodes::OP_RETURN)
      expect(chunks[2].data).to eq(data1)
      expect(chunks[3].data).to eq(data2)
    end

    it 'renders correct ASM' do
      script = described_class.op_return("\xde\xad".b)
      expect(script.to_asm).to eq('OP_0 OP_RETURN dead')
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
end
