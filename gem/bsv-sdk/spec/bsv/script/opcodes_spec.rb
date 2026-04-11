# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Script::Opcodes do
  describe 'constants' do
    it 'defines OP_0 as 0x00' do
      expect(described_class::OP_0).to eq(0x00)
    end

    it 'defines OP_FALSE as alias for OP_0' do
      expect(described_class::OP_FALSE).to eq(described_class::OP_0)
    end

    it 'defines OP_RETURN as 0x6a' do
      expect(described_class::OP_RETURN).to eq(0x6a)
    end

    it 'defines OP_DUP as 0x76' do
      expect(described_class::OP_DUP).to eq(0x76)
    end

    it 'defines OP_HASH160 as 0xa9' do
      expect(described_class::OP_HASH160).to eq(0xa9)
    end

    it 'defines OP_EQUALVERIFY as 0x88' do
      expect(described_class::OP_EQUALVERIFY).to eq(0x88)
    end

    it 'defines OP_CHECKSIG as 0xac' do
      expect(described_class::OP_CHECKSIG).to eq(0xac)
    end

    it 'defines OP_PUSHDATA1 as 0x4c' do
      expect(described_class::OP_PUSHDATA1).to eq(0x4c)
    end
  end

  describe '.name_for' do
    it 'returns the name for a known opcode' do
      expect(described_class.name_for(0x76)).to eq('OP_DUP')
    end

    it 'returns OP_0 for 0x00 (not OP_FALSE)' do
      # OP_0 is defined first, OP_FALSE is an alias
      expect(described_class.name_for(0x00)).to eq('OP_0')
    end

    it 'returns nil for unknown opcode' do
      expect(described_class.name_for(0xfe)).to eq('OP_PUBKEY')
    end
  end
end
