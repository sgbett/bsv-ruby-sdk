# frozen_string_literal: true

require 'spec_helper'

# Protocol conformance: Transaction templates
#
# Verifies that the SDK's script template constructors produce locking
# and unlocking scripts matching the BSV Hub protocol documentation.
#
# Source: https://hub.bsvblockchain.org/bitcoin-protocol-documentation/transaction-lifecycle/transaction-templates
# Source: https://hub.bsvblockchain.org/bsv-academy/bsv-academy/introduction-to-bitcoin-script/chapter-4-simple-scripts/03-pay-to-public-key-hash-p2pkh
# Source: https://hub.bsvblockchain.org/bsv-academy/bsv-academy/introduction-to-bitcoin-script/chapter-4-simple-scripts/01-pay-to-public-key-p2pk

# rubocop:disable RSpec/SpecFilePathFormat
RSpec.describe BSV::Script::Script do
  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  let(:public_key) { private_key.public_key }
  let(:pubkey_bytes) { public_key.compressed }
  let(:pubkey_hash) { public_key.hash160 }

  # Protocol docs: P2PKH locking script
  #   OP_DUP OP_HASH160 <Public Key Hash> OP_EQUALVERIFY OP_CHECKSIG
  describe 'P2PKH locking script' do
    subject(:script) { described_class.p2pkh_lock(pubkey_hash) }

    it 'produces the protocol-specified opcode sequence' do
      expect(script.to_asm).to eq(
        "OP_DUP OP_HASH160 #{pubkey_hash.unpack1('H*')} OP_EQUALVERIFY OP_CHECKSIG"
      )
    end

    it('is detected as p2pkh') { expect(script).to be_p2pkh }

    it('has exactly 25 bytes') { expect(script.to_binary.bytesize).to eq(25) }

    # Protocol docs: "The pubKeyHash in the Locking script is the
    # public key hashed twice: first with SHA-256 and then with RIPEMD-160."
    it 'embeds the HASH160 (SHA-256 then RIPEMD-160) of the public key' do
      sha256 = OpenSSL::Digest::SHA256.digest(pubkey_bytes)
      ripemd160 = OpenSSL::Digest::RIPEMD160.digest(sha256)
      expect(script.pubkey_hash).to eq(ripemd160)
    end
  end

  # Protocol docs: P2PKH unlocking script
  #   <Signature> <Public Key>
  describe 'P2PKH unlocking script' do
    subject(:script) { described_class.p2pkh_unlock(fake_sig, pubkey_bytes) }

    let(:fake_sig) { "0D#{"\x00" * 68}A" }

    it('contains two chunks') { expect(script.chunks.length).to eq(2) }

    it('has only data pushes') { expect(script.chunks).to all(be_data) }

    it('pushes the signature first') { expect(script.chunks[0].data).to eq(fake_sig) }

    it('pushes the public key second') { expect(script.chunks[1].data).to eq(pubkey_bytes) }
  end

  # Protocol docs: P2PK locking script
  #   <public_key> OP_CHECKSIG
  describe 'P2PK locking script' do
    subject(:script) { described_class.p2pk_lock(pubkey_bytes) }

    it 'produces the protocol-specified opcode sequence' do
      expect(script.to_asm).to eq("#{pubkey_bytes.unpack1('H*')} OP_CHECKSIG")
    end

    it('is detected as p2pk') { expect(script).to be_p2pk }
  end

  # Protocol docs: P2PK unlocking script
  #   <signature>
  describe 'P2PK unlocking script' do
    subject(:script) { described_class.p2pk_unlock(fake_sig) }

    let(:fake_sig) { "0D#{"\x00" * 68}A" }

    it('contains one data push') { expect(script.chunks.length).to eq(1) }

    it('pushes the signature') { expect(script.chunks[0].data).to eq(fake_sig) }
  end

  # Protocol docs: Multi-signature locking script (example: 2-of-3)
  #   OP_2 <pubKey1> <pubKey2> <pubKey3> OP_3 OP_CHECKMULTISIG
  describe 'P2MS (bare multisig) locking script' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    subject(:script) { described_class.p2ms_lock(2, ms_pubkeys) }

    let(:ms_keys) { Array.new(3) { BSV::Primitives::PrivateKey.generate.public_key } }
    let(:ms_pubkeys) { ms_keys.map(&:compressed) }

    it 'starts with OP_M (required signature count)' do
      expect(script.chunks.first.opcode).to eq(BSV::Script::Opcodes::OP_2)
    end

    it 'penultimate chunk is OP_N (total key count)' do
      expect(script.chunks[-2].opcode).to eq(BSV::Script::Opcodes::OP_3)
    end

    it 'ends with OP_CHECKMULTISIG' do
      expect(script.chunks[-1].opcode).to eq(BSV::Script::Opcodes::OP_CHECKMULTISIG)
    end

    it 'embeds all public keys between M and N' do
      expect(script.chunks[1..-3].map(&:data)).to eq(ms_pubkeys)
    end

    it('is detected as multisig') { expect(script).to be_multisig }
  end

  # Protocol docs: Multi-signature unlocking script
  #   OP_0 <sig1> <sig2>
  # The OP_0 dummy is the well-known OP_CHECKMULTISIG off-by-one bug workaround.
  describe 'P2MS (bare multisig) unlocking script' do
    subject(:script) { described_class.p2ms_unlock(*fake_sigs) }

    let(:fake_sigs) { Array.new(2) { "0D#{"\x00" * 68}A" } }

    it 'starts with OP_0 dummy element (off-by-one bug workaround)' do
      expect(script.chunks.first.opcode).to eq(BSV::Script::Opcodes::OP_0)
    end

    it 'pushes the correct number of signatures after the dummy' do
      expect(script.chunks[1..].length).to eq(2)
    end

    it 'pushes signatures in order' do
      expect(script.chunks[1..].map(&:data)).to eq(fake_sigs)
    end
  end

  # Protocol docs: OP_RETURN data carrier
  #   OP_FALSE OP_RETURN <arbitrary binary data>
  describe 'OP_RETURN data carrier script' do
    subject(:script) { described_class.op_return(data) }

    let(:data) { 'hello world' }

    it 'first chunk is OP_FALSE' do
      expect(script.chunks[0].opcode).to eq(BSV::Script::Opcodes::OP_FALSE)
    end

    it 'second chunk is OP_RETURN' do
      expect(script.chunks[1].opcode).to eq(BSV::Script::Opcodes::OP_RETURN)
    end

    it('embeds the data payload') { expect(script.op_return_data).to eq([data]) }

    it('is detected as op_return') { expect(script).to be_op_return }
  end

  # Protocol docs: "P2SH introduces functionality that is not compatible
  # with the Bitcoin protocol, nodes on the BSV network will evaluate any
  # transaction sent to the network that creates a P2SH output as invalid"
  describe 'P2SH compliance' do
    it('provides p2sh? detection') { expect(described_class.method_defined?(:p2sh?)).to be true }

    it('does not provide a p2sh_lock constructor') { expect(described_class).not_to respond_to(:p2sh_lock) }

    it 'detects P2SH pattern in existing scripts' do
      buf = [BSV::Script::Opcodes::OP_HASH160, 0x14].pack('CC')
      buf << ("\x00" * 20) << [BSV::Script::Opcodes::OP_EQUAL].pack('C')
      expect(described_class.new(buf)).to be_p2sh
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
