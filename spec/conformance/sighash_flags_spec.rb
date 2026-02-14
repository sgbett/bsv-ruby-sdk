# frozen_string_literal: true

require 'spec_helper'

# Protocol conformance: Sighash flags
#
# Verifies all sighash flag constants against the BSV Hub protocol
# documentation sighash flag reference.
#
# Source: https://hub.bsvblockchain.org/bsv-skills-center/important-concepts/details/sighash-flags
# Source: https://hub.bsvblockchain.org/bsv-academy/bsv-academy/bitcoin-primitives-digital-signatures/bsv-and-digital-signatures/ecdsa-secp256k1-for-bitcoin-transaction

RSpec.describe BSV::Transaction::Sighash do # rubocop:disable RSpec/SpecFilePathFormat
  # Protocol docs: "Currently all BitcoinSV transactions require an
  # additional SIGHASH flag called SIGHASH_FORKID which is 0x40"
  describe 'base flags' do
    it('SIGHASH_ALL = 0x01')          { expect(described_class::ALL).to eq(0x01) }
    it('SIGHASH_NONE = 0x02')         { expect(described_class::NONE).to eq(0x02) }
    it('SIGHASH_SINGLE = 0x03')       { expect(described_class::SINGLE).to eq(0x03) }
    it('SIGHASH_ANYONECANPAY = 0x80') { expect(described_class::ANYONE_CAN_PAY).to eq(0x80) }
    it('SIGHASH_FORKID = 0x40')       { expect(described_class::FORK_ID).to eq(0x40) }
  end

  # Protocol docs: "In BSV, all signatures also require SIGHASH_FORKID,
  # which adds 0x40 to the chosen SIGHASH value.
  # Example: SIGHASH_ALL (0x01) becomes 0x41."
  describe 'combined flags with FORKID' do
    # Protocol docs table — "Value including SIGHASH_FORKID"
    it 'SIGHASH_ALL | FORKID = 0x41 — sign all inputs and outputs' do
      expect(described_class::ALL_FORK_ID).to eq(0x41)
    end

    it 'SIGHASH_NONE | FORKID = 0x42 — sign all inputs, no outputs' do
      expect(described_class::NONE_FORK_ID).to eq(0x42)
    end

    it 'SIGHASH_SINGLE | FORKID = 0x43 — sign all inputs, matching output only' do
      expect(described_class::SINGLE_FORK_ID).to eq(0x43)
    end

    it 'SIGHASH_ALL | ANYONECANPAY | FORKID = 0xC1 — sign own input and all outputs' do
      expect(described_class::ALL_FORK_ID_ANYONE_CAN_PAY).to eq(0xc1)
    end

    it 'SIGHASH_NONE | ANYONECANPAY | FORKID = 0xC2 — sign own input, no outputs' do
      expect(described_class::NONE_FORK_ID_ANYONE_CAN_PAY).to eq(0xc2)
    end

    it 'SIGHASH_SINGLE | ANYONECANPAY | FORKID = 0xC3 — sign own input, matching output only' do
      expect(described_class::SINGLE_FORK_ID_ANYONE_CAN_PAY).to eq(0xc3)
    end
  end

  # Protocol docs: FORKID "adds 0x40 to the chosen SIGHASH value"
  describe 'FORKID composition' do
    it 'ALL | FORKID = ALL_FORK_ID' do
      expect(described_class::ALL | described_class::FORK_ID).to eq(described_class::ALL_FORK_ID)
    end

    it 'NONE | FORKID = NONE_FORK_ID' do
      expect(described_class::NONE | described_class::FORK_ID).to eq(described_class::NONE_FORK_ID)
    end

    it 'SINGLE | FORKID = SINGLE_FORK_ID' do
      expect(described_class::SINGLE | described_class::FORK_ID).to eq(described_class::SINGLE_FORK_ID)
    end
  end

  # Protocol docs: ANYONECANPAY "can be combined with the others"
  describe 'ANYONECANPAY composition' do
    it 'ALL_FORK_ID | ANYONECANPAY = ALL_FORK_ID_ANYONE_CAN_PAY' do
      expect(described_class::ALL_FORK_ID | described_class::ANYONE_CAN_PAY)
        .to eq(described_class::ALL_FORK_ID_ANYONE_CAN_PAY)
    end

    it 'NONE_FORK_ID | ANYONECANPAY = NONE_FORK_ID_ANYONE_CAN_PAY' do
      expect(described_class::NONE_FORK_ID | described_class::ANYONE_CAN_PAY)
        .to eq(described_class::NONE_FORK_ID_ANYONE_CAN_PAY)
    end

    it 'SINGLE_FORK_ID | ANYONECANPAY = SINGLE_FORK_ID_ANYONE_CAN_PAY' do
      expect(described_class::SINGLE_FORK_ID | described_class::ANYONE_CAN_PAY)
        .to eq(described_class::SINGLE_FORK_ID_ANYONE_CAN_PAY)
    end
  end

  describe 'MASK extracts base type' do
    # Protocol docs: "Only one of SIGHASH_ALL, SIGHASH_SINGLE and
    # SIGHASH_NONE can be used in any signature"
    it 'extracts ALL from ALL_FORK_ID' do
      expect(described_class::ALL_FORK_ID & described_class::MASK).to eq(described_class::ALL)
    end

    it 'extracts NONE from NONE_FORK_ID_ANYONE_CAN_PAY' do
      expect(described_class::NONE_FORK_ID_ANYONE_CAN_PAY & described_class::MASK)
        .to eq(described_class::NONE)
    end

    it 'extracts SINGLE from SINGLE_FORK_ID' do
      expect(described_class::SINGLE_FORK_ID & described_class::MASK).to eq(described_class::SINGLE)
    end
  end
end
