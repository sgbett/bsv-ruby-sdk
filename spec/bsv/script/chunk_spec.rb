# frozen_string_literal: true

RSpec.describe BSV::Script::Chunk do
  describe '#to_binary' do
    it 'serialises a bare opcode' do
      chunk = described_class.new(opcode: BSV::Script::Opcodes::OP_DUP)
      expect(chunk.to_binary).to eq("\x76".b)
    end

    it 'serialises a small data push (<=75 bytes)' do
      data = "\x01\x02\x03".b
      chunk = described_class.new(opcode: 3, data: data)
      expect(chunk.to_binary).to eq("\x03\x01\x02\x03".b)
    end

    it 'serialises a 32-byte data push' do
      data = "\xab".b * 32
      chunk = described_class.new(opcode: 0x20, data: data)
      expect(chunk.to_binary).to eq("\x20".b + data)
    end

    it 'serialises OP_PUSHDATA1 for 76-255 byte data' do
      data = 'x'.b * 100
      chunk = described_class.new(opcode: BSV::Script::Opcodes::OP_PUSHDATA1, data: data)
      expected = "\x4c\x64".b + data # 0x4c, length=100, data
      expect(chunk.to_binary).to eq(expected)
    end
  end

  describe '#to_asm' do
    it 'renders an opcode as its name' do
      chunk = described_class.new(opcode: BSV::Script::Opcodes::OP_CHECKSIG)
      expect(chunk.to_asm).to eq('OP_CHECKSIG')
    end

    it 'renders data as hex' do
      data = "\xde\xad\xbe\xef".b
      chunk = described_class.new(opcode: 4, data: data)
      expect(chunk.to_asm).to eq('deadbeef')
    end
  end

  describe '#data?' do
    it 'returns true for data chunks' do
      chunk = described_class.new(opcode: 1, data: "\x01".b)
      expect(chunk.data?).to be true
    end

    it 'returns false for bare opcode chunks' do
      chunk = described_class.new(opcode: BSV::Script::Opcodes::OP_DUP)
      expect(chunk.data?).to be false
    end
  end

  describe '#==' do
    it 'considers identical chunks equal' do
      a = described_class.new(opcode: BSV::Script::Opcodes::OP_DUP)
      b = described_class.new(opcode: BSV::Script::Opcodes::OP_DUP)
      expect(a).to eq(b)
    end
  end
end
