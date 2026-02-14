# frozen_string_literal: true

require 'spec_helper'

# Protocol conformance: Opcode constants
#
# Verifies every opcode constant in BSV::Script::Opcodes against the
# BSV Hub protocol documentation opcode reference.
#
# Source: https://hub.bsvblockchain.org/bitcoin-protocol-documentation/transaction-lifecycle/opcodes-used-in-script

RSpec.describe BSV::Script::Opcodes do # rubocop:disable RSpec/SpecFilePathFormat
  # Protocol docs: "An empty array of bytes is pushed onto the stack"
  # Also aliased as OP_FALSE
  describe 'constants: push value' do
    it('OP_0 / OP_FALSE = 0x00') { expect(described_class::OP_0).to eq(0x00) }
    it('OP_FALSE aliases OP_0')  { expect(described_class::OP_FALSE).to eq(described_class::OP_0) }

    # Protocol docs: "The next opcode bytes is data to be pushed onto the stack" (0x01-0x4b)
    # These are implicit (byte value IS the length), not defined as named constants.

    it('OP_PUSHDATA1 = 0x4c') { expect(described_class::OP_PUSHDATA1).to eq(0x4c) }
    it('OP_PUSHDATA2 = 0x4d') { expect(described_class::OP_PUSHDATA2).to eq(0x4d) }
    it('OP_PUSHDATA4 = 0x4e') { expect(described_class::OP_PUSHDATA4).to eq(0x4e) }
    it('OP_1NEGATE = 0x4f')   { expect(described_class::OP_1NEGATE).to eq(0x4f) }

    # Protocol docs: OP_RESERVED is 0x50, "Invalid unless in unexecuted OP_IF branch"
    it('OP_RESERVED = 0x50') { expect(described_class::OP_RESERVED).to eq(0x50) }

    it('OP_1 / OP_TRUE = 0x51') { expect(described_class::OP_1).to eq(0x51) }
    it('OP_TRUE aliases OP_1')  { expect(described_class::OP_TRUE).to eq(described_class::OP_1) }

    # Protocol docs: "The number in the word name (2-16) is pushed onto the stack"
    it('OP_2 = 0x52')  { expect(described_class::OP_2).to eq(0x52) }
    it('OP_3 = 0x53')  { expect(described_class::OP_3).to eq(0x53) }
    it('OP_4 = 0x54')  { expect(described_class::OP_4).to eq(0x54) }
    it('OP_5 = 0x55')  { expect(described_class::OP_5).to eq(0x55) }
    it('OP_6 = 0x56')  { expect(described_class::OP_6).to eq(0x56) }
    it('OP_7 = 0x57')  { expect(described_class::OP_7).to eq(0x57) }
    it('OP_8 = 0x58')  { expect(described_class::OP_8).to eq(0x58) }
    it('OP_9 = 0x59')  { expect(described_class::OP_9).to eq(0x59) }
    it('OP_10 = 0x5a') { expect(described_class::OP_10).to eq(0x5a) }
    it('OP_11 = 0x5b') { expect(described_class::OP_11).to eq(0x5b) }
    it('OP_12 = 0x5c') { expect(described_class::OP_12).to eq(0x5c) }
    it('OP_13 = 0x5d') { expect(described_class::OP_13).to eq(0x5d) }
    it('OP_14 = 0x5e') { expect(described_class::OP_14).to eq(0x5e) }
    it('OP_15 = 0x5f') { expect(described_class::OP_15).to eq(0x5f) }
    it('OP_16 = 0x60') { expect(described_class::OP_16).to eq(0x60) }
  end

  describe 'constants: flow control' do
    it('OP_NOP = 0x61')      { expect(described_class::OP_NOP).to eq(0x61) }
    it('OP_VER = 0x62')      { expect(described_class::OP_VER).to eq(0x62) }
    it('OP_IF = 0x63')       { expect(described_class::OP_IF).to eq(0x63) }
    it('OP_NOTIF = 0x64')    { expect(described_class::OP_NOTIF).to eq(0x64) }
    it('OP_VERIF = 0x65')    { expect(described_class::OP_VERIF).to eq(0x65) }
    it('OP_VERNOTIF = 0x66') { expect(described_class::OP_VERNOTIF).to eq(0x66) }
    it('OP_ELSE = 0x67')     { expect(described_class::OP_ELSE).to eq(0x67) }
    it('OP_ENDIF = 0x68')    { expect(described_class::OP_ENDIF).to eq(0x68) }
    it('OP_VERIFY = 0x69')   { expect(described_class::OP_VERIFY).to eq(0x69) }
    it('OP_RETURN = 0x6a')   { expect(described_class::OP_RETURN).to eq(0x6a) }
  end

  describe 'constants: stack operations' do
    it('OP_TOALTSTACK = 0x6b')   { expect(described_class::OP_TOALTSTACK).to eq(0x6b) }
    it('OP_FROMALTSTACK = 0x6c') { expect(described_class::OP_FROMALTSTACK).to eq(0x6c) }
    it('OP_2DROP = 0x6d')        { expect(described_class::OP_2DROP).to eq(0x6d) }
    it('OP_2DUP = 0x6e')         { expect(described_class::OP_2DUP).to eq(0x6e) }
    it('OP_3DUP = 0x6f')         { expect(described_class::OP_3DUP).to eq(0x6f) }
    it('OP_2OVER = 0x70')        { expect(described_class::OP_2OVER).to eq(0x70) }
    it('OP_2ROT = 0x71')         { expect(described_class::OP_2ROT).to eq(0x71) }
    it('OP_2SWAP = 0x72')        { expect(described_class::OP_2SWAP).to eq(0x72) }
    it('OP_IFDUP = 0x73')        { expect(described_class::OP_IFDUP).to eq(0x73) }
    it('OP_DEPTH = 0x74')        { expect(described_class::OP_DEPTH).to eq(0x74) }
    it('OP_DROP = 0x75')         { expect(described_class::OP_DROP).to eq(0x75) }
    it('OP_DUP = 0x76')          { expect(described_class::OP_DUP).to eq(0x76) }
    it('OP_NIP = 0x77')          { expect(described_class::OP_NIP).to eq(0x77) }
    it('OP_OVER = 0x78')         { expect(described_class::OP_OVER).to eq(0x78) }
    it('OP_PICK = 0x79')         { expect(described_class::OP_PICK).to eq(0x79) }
    it('OP_ROLL = 0x7a')         { expect(described_class::OP_ROLL).to eq(0x7a) }
    it('OP_ROT = 0x7b')          { expect(described_class::OP_ROT).to eq(0x7b) }
    it('OP_SWAP = 0x7c')         { expect(described_class::OP_SWAP).to eq(0x7c) }
    it('OP_TUCK = 0x7d')         { expect(described_class::OP_TUCK).to eq(0x7d) }
  end

  describe 'constants: splice / data manipulation' do
    it('OP_CAT = 0x7e')     { expect(described_class::OP_CAT).to eq(0x7e) }
    it('OP_SPLIT = 0x7f')   { expect(described_class::OP_SPLIT).to eq(0x7f) }
    it('OP_NUM2BIN = 0x80') { expect(described_class::OP_NUM2BIN).to eq(0x80) }
    it('OP_BIN2NUM = 0x81') { expect(described_class::OP_BIN2NUM).to eq(0x81) }
    it('OP_SIZE = 0x82')    { expect(described_class::OP_SIZE).to eq(0x82) }
  end

  describe 'constants: bitwise logic' do
    it('OP_INVERT = 0x83')      { expect(described_class::OP_INVERT).to eq(0x83) }
    it('OP_AND = 0x84')         { expect(described_class::OP_AND).to eq(0x84) }
    it('OP_OR = 0x85')          { expect(described_class::OP_OR).to eq(0x85) }
    it('OP_XOR = 0x86')         { expect(described_class::OP_XOR).to eq(0x86) }
    it('OP_EQUAL = 0x87')       { expect(described_class::OP_EQUAL).to eq(0x87) }
    it('OP_EQUALVERIFY = 0x88') { expect(described_class::OP_EQUALVERIFY).to eq(0x88) }

    # Protocol docs: "Invalid unless in unexecuted OP_IF branch"
    it('OP_RESERVED1 = 0x89') { expect(described_class::OP_RESERVED1).to eq(0x89) }
    it('OP_RESERVED2 = 0x8a') { expect(described_class::OP_RESERVED2).to eq(0x8a) }
  end

  describe 'constants: arithmetic' do
    it('OP_1ADD = 0x8b')        { expect(described_class::OP_1ADD).to eq(0x8b) }
    it('OP_1SUB = 0x8c')        { expect(described_class::OP_1SUB).to eq(0x8c) }
    it('OP_2MUL = 0x8d')        { expect(described_class::OP_2MUL).to eq(0x8d) }
    it('OP_2DIV = 0x8e')        { expect(described_class::OP_2DIV).to eq(0x8e) }
    it('OP_NEGATE = 0x8f')      { expect(described_class::OP_NEGATE).to eq(0x8f) }
    it('OP_ABS = 0x90')         { expect(described_class::OP_ABS).to eq(0x90) }
    it('OP_NOT = 0x91')         { expect(described_class::OP_NOT).to eq(0x91) }
    it('OP_0NOTEQUAL = 0x92')   { expect(described_class::OP_0NOTEQUAL).to eq(0x92) }
    it('OP_ADD = 0x93')         { expect(described_class::OP_ADD).to eq(0x93) }
    it('OP_SUB = 0x94')         { expect(described_class::OP_SUB).to eq(0x94) }
    it('OP_MUL = 0x95')         { expect(described_class::OP_MUL).to eq(0x95) }
    it('OP_DIV = 0x96')         { expect(described_class::OP_DIV).to eq(0x96) }
    it('OP_MOD = 0x97')         { expect(described_class::OP_MOD).to eq(0x97) }
    it('OP_LSHIFT = 0x98')      { expect(described_class::OP_LSHIFT).to eq(0x98) }
    it('OP_RSHIFT = 0x99')      { expect(described_class::OP_RSHIFT).to eq(0x99) }
    it('OP_BOOLAND = 0x9a')     { expect(described_class::OP_BOOLAND).to eq(0x9a) }
    it('OP_BOOLOR = 0x9b')      { expect(described_class::OP_BOOLOR).to eq(0x9b) }
    it('OP_NUMEQUAL = 0x9c')    { expect(described_class::OP_NUMEQUAL).to eq(0x9c) }
    it('OP_NUMEQUALVERIFY = 0x9d')    { expect(described_class::OP_NUMEQUALVERIFY).to eq(0x9d) }
    it('OP_NUMNOTEQUAL = 0x9e')       { expect(described_class::OP_NUMNOTEQUAL).to eq(0x9e) }
    it('OP_LESSTHAN = 0x9f')          { expect(described_class::OP_LESSTHAN).to eq(0x9f) }
    it('OP_GREATERTHAN = 0xa0')       { expect(described_class::OP_GREATERTHAN).to eq(0xa0) }
    it('OP_LESSTHANOREQUAL = 0xa1')   { expect(described_class::OP_LESSTHANOREQUAL).to eq(0xa1) }
    it('OP_GREATERTHANOREQUAL = 0xa2') { expect(described_class::OP_GREATERTHANOREQUAL).to eq(0xa2) }
    it('OP_MIN = 0xa3')               { expect(described_class::OP_MIN).to eq(0xa3) }
    it('OP_MAX = 0xa4')               { expect(described_class::OP_MAX).to eq(0xa4) }
    it('OP_WITHIN = 0xa5')            { expect(described_class::OP_WITHIN).to eq(0xa5) }
  end

  describe 'constants: cryptography' do
    it('OP_RIPEMD160 = 0xa6')          { expect(described_class::OP_RIPEMD160).to eq(0xa6) }
    it('OP_SHA1 = 0xa7')               { expect(described_class::OP_SHA1).to eq(0xa7) }
    it('OP_SHA256 = 0xa8')             { expect(described_class::OP_SHA256).to eq(0xa8) }
    it('OP_HASH160 = 0xa9')            { expect(described_class::OP_HASH160).to eq(0xa9) }
    it('OP_HASH256 = 0xaa')            { expect(described_class::OP_HASH256).to eq(0xaa) }
    it('OP_CODESEPARATOR = 0xab')      { expect(described_class::OP_CODESEPARATOR).to eq(0xab) }
    it('OP_CHECKSIG = 0xac')           { expect(described_class::OP_CHECKSIG).to eq(0xac) }
    it('OP_CHECKSIGVERIFY = 0xad')     { expect(described_class::OP_CHECKSIGVERIFY).to eq(0xad) }
    it('OP_CHECKMULTISIG = 0xae')      { expect(described_class::OP_CHECKMULTISIG).to eq(0xae) }
    it('OP_CHECKMULTISIGVERIFY = 0xaf') { expect(described_class::OP_CHECKMULTISIGVERIFY).to eq(0xaf) }
  end

  # Protocol docs: OP_NOP2 (formerly OP_CHECKLOCKTIMEVERIFY) = 0xb1,
  #                OP_NOP3 (formerly OP_CHECKSEQUENCEVERIFY) = 0xb2
  # "Functionally OP_NOP on post-genesis UTXOs"
  describe 'constants: expansion / NOP' do
    it('OP_NOP1 = 0xb0') { expect(described_class::OP_NOP1).to eq(0xb0) }
    it('OP_CHECKLOCKTIMEVERIFY = 0xb1') { expect(described_class::OP_CHECKLOCKTIMEVERIFY).to eq(0xb1) }
    it('OP_CHECKSEQUENCEVERIFY = 0xb2') { expect(described_class::OP_CHECKSEQUENCEVERIFY).to eq(0xb2) }
    it('OP_NOP4 = 0xb3')  { expect(described_class::OP_NOP4).to eq(0xb3) }
    it('OP_NOP5 = 0xb4')  { expect(described_class::OP_NOP5).to eq(0xb4) }
    it('OP_NOP6 = 0xb5')  { expect(described_class::OP_NOP6).to eq(0xb5) }
    it('OP_NOP7 = 0xb6')  { expect(described_class::OP_NOP7).to eq(0xb6) }
    it('OP_NOP8 = 0xb7')  { expect(described_class::OP_NOP8).to eq(0xb7) }
    it('OP_NOP9 = 0xb8')  { expect(described_class::OP_NOP9).to eq(0xb8) }
    it('OP_NOP10 = 0xb9') { expect(described_class::OP_NOP10).to eq(0xb9) }
  end

  # Protocol docs: "Represents a public key hashed with OP_HASH160" etc.
  # These are pseudo-words used for documentation, not executed in scripts.
  describe 'constants: pseudo-words' do
    it('OP_PUBKEYHASH = 0xfd')    { expect(described_class::OP_PUBKEYHASH).to eq(0xfd) }
    it('OP_PUBKEY = 0xfe')        { expect(described_class::OP_PUBKEY).to eq(0xfe) }
    it('OP_INVALIDOPCODE = 0xff') { expect(described_class::OP_INVALIDOPCODE).to eq(0xff) }
  end

  describe 'reverse lookup via name_for' do
    {
      0x00 => 'OP_0',
      0x4c => 'OP_PUSHDATA1',
      0x4f => 'OP_1NEGATE',
      0x51 => 'OP_1',
      0x61 => 'OP_NOP',
      0x6a => 'OP_RETURN',
      0x76 => 'OP_DUP',
      0x87 => 'OP_EQUAL',
      0x93 => 'OP_ADD',
      0xa9 => 'OP_HASH160',
      0xac => 'OP_CHECKSIG',
      0xae => 'OP_CHECKMULTISIG',
      0xb0 => 'OP_NOP1',
      0xfd => 'OP_PUBKEYHASH',
      0xff => 'OP_INVALIDOPCODE'
    }.each do |byte, name|
      it "resolves 0x#{byte.to_s(16).rjust(2, '0')} to #{name}" do
        expect(described_class.name_for(byte)).to eq(name)
      end
    end
  end

  # Protocol docs list specific opcodes as DISABLED
  describe 'disabled opcodes are defined but documented' do
    # Protocol docs: OP_VER "DISABLED", OP_VERIF "DISABLED", OP_VERNOTIF "DISABLED"
    it('OP_VER is defined (0x62, disabled)') { expect(described_class::OP_VER).to eq(0x62) }
    it('OP_VERIF is defined (0x65, disabled)')     { expect(described_class::OP_VERIF).to eq(0x65) }
    it('OP_VERNOTIF is defined (0x66, disabled)')  { expect(described_class::OP_VERNOTIF).to eq(0x66) }

    # Protocol docs: OP_2MUL "DISABLED", OP_2DIV "DISABLED"
    it('OP_2MUL is defined (0x8d, disabled)')  { expect(described_class::OP_2MUL).to eq(0x8d) }
    it('OP_2DIV is defined (0x8e, disabled)')  { expect(described_class::OP_2DIV).to eq(0x8e) }
  end

  describe 'completeness' do
    described_class.constants
                   .select { |c| c.to_s.start_with?('OP_') }
                   .reject { |c| %i[OP_FALSE OP_TRUE].include?(c) }
                   .each do |name|
                     hex = described_class.const_get(name).to_s(16).rjust(2, '0')

                     it "#{name} is a valid byte value (0x#{hex})" do
                       expect(described_class.const_get(name)).to be_a(Integer).and be_between(0x00, 0xff)
                     end
    end
  end
end
