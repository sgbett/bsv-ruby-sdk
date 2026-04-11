# frozen_string_literal: true

RSpec.describe BSV::Script::Builder do
  describe '#push_op' do
    it 'appends an opcode by symbol' do
      script = described_class.new.push_op(:OP_DUP).build
      expect(script.chunks.length).to eq(1)
      expect(script.chunks[0].opcode).to eq(BSV::Script::Opcodes::OP_DUP)
    end

    it 'appends an opcode by integer' do
      script = described_class.new.push_op(0x76).build
      expect(script.chunks[0].opcode).to eq(BSV::Script::Opcodes::OP_DUP)
    end

    it 'raises NameError for unknown symbol' do
      expect { described_class.new.push_op(:OP_NONSENSE) }.to raise_error(NameError)
    end
  end

  describe '#push_data' do
    it 'pushes small data (<=75 bytes) with direct push' do
      data = "\x01".b * 20
      script = described_class.new.push_data(data).build
      chunk = script.chunks[0]

      expect(chunk.data).to eq(data)
      expect(chunk.opcode).to eq(20) # direct push length
    end

    it 'pushes 76-255 byte data with OP_PUSHDATA1' do
      data = "\xab".b * 100
      script = described_class.new.push_data(data).build
      chunk = script.chunks[0]

      expect(chunk.data).to eq(data)
      expect(chunk.opcode).to eq(BSV::Script::Opcodes::OP_PUSHDATA1)
    end

    it 'pushes 256+ byte data with OP_PUSHDATA2' do
      data = "\xcd".b * 300
      script = described_class.new.push_data(data).build
      chunk = script.chunks[0]

      expect(chunk.data).to eq(data)
      expect(chunk.opcode).to eq(BSV::Script::Opcodes::OP_PUSHDATA2)
    end
  end

  describe '#push_hex' do
    it 'converts hex to binary and pushes' do
      script = described_class.new.push_hex('deadbeef').build
      expect(script.chunks[0].data).to eq("\xde\xad\xbe\xef".b)
    end
  end

  describe '#build' do
    it 'returns a BSV::Script::Script instance' do
      script = described_class.new.build
      expect(script).to be_a(BSV::Script::Script)
    end

    it 'produces an empty script from empty builder' do
      script = described_class.new.build
      expect(script.length).to eq(0)
      expect(script.to_hex).to eq('')
    end
  end

  describe 'chaining' do
    it 'returns self from each method' do
      builder = described_class.new
      expect(builder.push_op(:OP_DUP)).to be(builder)
      expect(builder.push_data("\x01".b)).to be(builder)
      expect(builder.push_hex('ff')).to be(builder)
    end
  end

  describe 'round-trip equivalence' do
    it 'matches Script.p2pkh_lock' do
      pubkey_hash = "\x04\xff\x36\x7b\xe7\x19\xef\xa7\x9d\x76\xe4\x41\x6f\xfb\x07\x2c\xd5\x3b\x20\x88".b

      built = described_class.new
                             .push_op(:OP_DUP)
                             .push_op(:OP_HASH160)
                             .push_data(pubkey_hash)
                             .push_op(:OP_EQUALVERIFY)
                             .push_op(:OP_CHECKSIG)
                             .build

      template = BSV::Script::Script.p2pkh_lock(pubkey_hash)

      expect(built.to_hex).to eq(template.to_hex)
    end

    it 'matches Script.op_return' do
      data = 'hello world'.b

      built = described_class.new
                             .push_op(:OP_FALSE)
                             .push_op(:OP_RETURN)
                             .push_data(data)
                             .build

      template = BSV::Script::Script.op_return(data)

      expect(built.to_hex).to eq(template.to_hex)
    end
  end

  describe 'Script.builder factory' do
    it 'returns a Builder instance' do
      expect(BSV::Script::Script.builder).to be_a(described_class)
    end
  end
end
