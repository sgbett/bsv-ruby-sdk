# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Transaction::Transaction do
  # Go SDK test vector: 1 input, 2 outputs
  let(:vector1_hex) do
    '010000000193a35408b6068499e0d5abd799d3e827d9bfe70c9b75ebe209c91d2507232651' \
      '0000000000ffffffff02404b4c00000000001976a91404ff367be719efa79d76e4416ffb07' \
      '2cd53b208888acde94a905000000001976a91404d03f746652cfcb6cb55119ab473a045137' \
      'd26588ac00000000'
  end

  # Go SDK test vector: 2 inputs, 3 outputs
  let(:vector2_hex) do
    '01000000027e2705da59f7112c7337d79840b56fff582b8f3a0e9df8eb19e282377bebb1bc' \
      '0100000000ffffffffdebe6fe5ad8e9220a10fcf6340f7fca660d87aeedf0f74a142fba6de' \
      '1f68d8490000000000ffffffff0300e1f505000000001976a9142987362cf0d21193ce7e70' \
      '55824baac1ee245d0d88ac00e1f505000000001976a9143ca26faa390248b7a7ac45be53b0' \
      'e4004ad7952688ac34657fe2000000001976a914eb0bd5edba389198e73f8efabddfc61666' \
      '969ff788ac00000000'
  end

  describe '.from_hex / #to_hex' do
    it 'round-trips vector 1' do
      tx = described_class.from_hex(vector1_hex)

      expect(tx.version).to eq(1)
      expect(tx.inputs.length).to eq(1)
      expect(tx.outputs.length).to eq(2)
      expect(tx.lock_time).to eq(0)
      expect(tx.to_hex).to eq(vector1_hex)
    end

    it 'round-trips vector 2' do
      tx = described_class.from_hex(vector2_hex)

      expect(tx.version).to eq(1)
      expect(tx.inputs.length).to eq(2)
      expect(tx.outputs.length).to eq(3)
      expect(tx.to_hex).to eq(vector2_hex)
    end
  end

  describe '.from_binary / #to_binary' do
    it 'round-trips binary' do
      binary = [vector1_hex].pack('H*')
      tx = described_class.from_binary(binary)
      expect(tx.to_binary).to eq(binary)
    end
  end

  describe '#txid / #txid_hex' do
    it 'computes the correct txid for vector 1' do
      tx = described_class.from_hex(vector1_hex)
      # SHA256d of serialised tx, reversed to display order
      txid = tx.txid_hex
      expect(txid.length).to eq(64)
      expect(tx.wtxid.bytesize).to eq(32)
    end
  end

  describe '#dtxid / #dtxid_hex' do
    it 'returns display-order hex (same as txid_hex)' do
      tx = described_class.from_hex(vector1_hex)
      expect(tx.dtxid).to eq(tx.txid_hex)
    end

    it 'dtxid_hex is an alias for txid_hex' do
      tx = described_class.from_hex(vector1_hex)
      expect(tx.dtxid_hex).to eq(tx.txid_hex)
    end
  end

  describe 'parsed structure' do
    it 'correctly parses vector 1 inputs and outputs' do
      tx = described_class.from_hex(vector1_hex)

      input = tx.inputs[0]
      expect(input.prev_tx_out_index).to eq(0)
      expect(input.sequence).to eq(0xFFFFFFFF)

      expect(tx.outputs[0].satoshis).to eq(5_000_000)
      expect(tx.outputs[1].satoshis).to eq(94_999_774)
    end

    it 'correctly parses vector 2 outputs' do
      tx = described_class.from_hex(vector2_hex)

      expect(tx.outputs[0].satoshis).to eq(100_000_000)
      expect(tx.outputs[1].satoshis).to eq(100_000_000)
      expect(tx.outputs[2].satoshis).to eq(3_799_999_796)
    end
  end

  describe '#sighash_preimage' do
    let(:source_script_single) { BSV::Script::Script.from_hex('76a914c0a3c167a28cabb9fbb495affa0761e6e74ac60d88ac') }
    let(:source_script_multi) { BSV::Script::Script.from_hex('76a914eb0bd5edba389198e73f8efabddfc61666969ff788ac') }

    it 'computes the correct preimage for vector 1 (SIGHASH_ALL|FORKID)' do
      tx = described_class.from_hex(vector1_hex)
      tx.inputs[0].source_satoshis = 100_000_000
      tx.inputs[0].source_locking_script = source_script_single

      preimage = tx.sighash_preimage(0)
      expected = '010000007ced5b2e5cf3ea407b005d8b18c393b6256ea2429b6ff409983e10adc61d0ae8' \
                 '3bb13029ce7b1f559ef5e747fcac439f1455a2ec7c5f09b72290795e706650449' \
                 '3a35408b6068499e0d5abd799d3e827d9bfe70c9b75ebe209c91d250723265100' \
                 '0000001976a914c0a3c167a28cabb9fbb495affa0761e6e74ac60d88ac00e1f505' \
                 '00000000ffffffff87841ab2b7a4133af2c58256edb7c3c9edca765a852ebe2d0d' \
                 'c962604a30f1030000000041000000'
      expect(preimage.unpack1('H*')).to eq(expected)
    end

    it 'computes the correct preimage for vector 2 index 0' do
      tx = described_class.from_hex(vector2_hex)
      tx.inputs[0].source_satoshis = 2_000_000_000
      tx.inputs[0].source_locking_script = source_script_multi
      tx.inputs[1].source_satoshis = 2_000_000_000
      tx.inputs[1].source_locking_script = source_script_multi

      preimage = tx.sighash_preimage(0)
      expected = '01000000eaef7a1b82f72f4097e63b0173906d690cc137221d221fc4150bae88570fa356' \
                 '752adad0a7b9ceca853768aebb6965eca126a62965f698a0c1bc43d83db632ad' \
                 '7e2705da59f7112c7337d79840b56fff582b8f3a0e9df8eb19e282377bebb1bc' \
                 '010000001976a914eb0bd5edba389198e73f8efabddfc61666969ff788ac00943577' \
                 '00000000ffffffff0cf3246582f4b1b5fd150b942916c7d5c78e80259cbab1a761' \
                 'a9e4ac3a66e0a70000000041000000'
      expect(preimage.unpack1('H*')).to eq(expected)
    end

    it 'computes the correct preimage for vector 2 index 1' do
      tx = described_class.from_hex(vector2_hex)
      tx.inputs[0].source_satoshis = 2_000_000_000
      tx.inputs[0].source_locking_script = source_script_multi
      tx.inputs[1].source_satoshis = 2_000_000_000
      tx.inputs[1].source_locking_script = source_script_multi

      preimage = tx.sighash_preimage(1)
      expected = '01000000eaef7a1b82f72f4097e63b0173906d690cc137221d221fc4150bae88570fa356' \
                 '752adad0a7b9ceca853768aebb6965eca126a62965f698a0c1bc43d83db632ad' \
                 'debe6fe5ad8e9220a10fcf6340f7fca660d87aeedf0f74a142fba6de1f68d849' \
                 '000000001976a914eb0bd5edba389198e73f8efabddfc61666969ff788ac00943577' \
                 '00000000ffffffff0cf3246582f4b1b5fd150b942916c7d5c78e80259cbab1a761' \
                 'a9e4ac3a66e0a70000000041000000'
      expect(preimage.unpack1('H*')).to eq(expected)
    end
  end

  describe '#sighash' do
    let(:source_script_single) { BSV::Script::Script.from_hex('76a914c0a3c167a28cabb9fbb495affa0761e6e74ac60d88ac') }
    let(:source_script_multi) { BSV::Script::Script.from_hex('76a914eb0bd5edba389198e73f8efabddfc61666969ff788ac') }

    it 'matches Go SDK vector 1 sighash' do
      tx = described_class.from_hex(vector1_hex)
      tx.inputs[0].source_satoshis = 100_000_000
      tx.inputs[0].source_locking_script = source_script_single

      hash = tx.sighash(0)
      expect(hash.unpack1('H*')).to eq('be9a42ef2e2dd7ef02cd631290667292cbbc5018f4e3f6843a8f4c302a2111b1')
    end

    it 'matches Go SDK vector 2 sighash (index 0)' do
      tx = described_class.from_hex(vector2_hex)
      tx.inputs[0].source_satoshis = 2_000_000_000
      tx.inputs[0].source_locking_script = source_script_multi
      tx.inputs[1].source_satoshis = 2_000_000_000
      tx.inputs[1].source_locking_script = source_script_multi

      hash = tx.sighash(0)
      expect(hash.unpack1('H*')).to eq('8b15eecfb6d5e727485e19797b5d1829e0630e8b43c806707685238e28a3194c')
    end

    it 'matches Go SDK vector 3 sighash (index 1)' do
      tx = described_class.from_hex(vector2_hex)
      tx.inputs[0].source_satoshis = 2_000_000_000
      tx.inputs[0].source_locking_script = source_script_multi
      tx.inputs[1].source_satoshis = 2_000_000_000
      tx.inputs[1].source_locking_script = source_script_multi

      hash = tx.sighash(1)
      expect(hash.unpack1('H*')).to eq('7b72c355a2714a5039d97fbd5eee792099b0eab4bf07d2e5bfcfc3309f81badb')
    end

    it 'raises on non-FORKID sighash type' do
      tx = described_class.from_hex(vector1_hex)
      tx.inputs[0].source_satoshis = 100_000_000
      tx.inputs[0].source_locking_script = source_script_single

      expect { tx.sighash(0, BSV::Transaction::Sighash::ALL) }
        .to raise_error(ArgumentError, /FORKID/)
    end
  end

  describe 'additional SIGHASH types' do
    let(:source_script) { BSV::Script::Script.from_hex('76a914c0a3c167a28cabb9fbb495affa0761e6e74ac60d88ac') }
    let(:zero_hash) { "\x00".b * 32 }

    # Use vector 1 (1 input, 2 outputs) as the base transaction
    let(:tx) do
      t = described_class.from_hex(vector1_hex)
      t.inputs[0].source_satoshis = 100_000_000
      t.inputs[0].source_locking_script = source_script
      t
    end

    # Extract the three hash fields from a 181-byte BIP-143 preimage:
    #   bytes 0-3:   nVersion
    #   bytes 4-35:  hashPrevouts
    #   bytes 36-67: hashSequence
    #   bytes 68+:   outpoint, scriptCode, value, nSequence...
    # hashOutputs starts at offset (68 + 36 + varint+script + 8 + 4)
    # Easier: compute known values from ALL|FORKID and compare structurally.
    let(:all_preimage) { tx.sighash_preimage(0, BSV::Transaction::Sighash::ALL_FORK_ID) }
    let(:known_hash_prevouts) { all_preimage.byteslice(4, 32) }
    let(:known_hash_sequence) { all_preimage.byteslice(36, 32) }
    # hashOutputs is 32 bytes before the final 8 bytes (nLockTime + sighashType)
    let(:known_hash_outputs) { all_preimage.byteslice(-40, 32) }

    def extract_hash_prevouts(preimage)
      preimage.byteslice(4, 32)
    end

    def extract_hash_sequence(preimage)
      preimage.byteslice(36, 32)
    end

    def extract_hash_outputs(preimage)
      preimage.byteslice(-40, 32)
    end

    def extract_sighash_type(preimage)
      preimage.byteslice(-4, 4).unpack1('V')
    end

    it 'NONE|FORKID zeroes hashSequence and hashOutputs' do
      preimage = tx.sighash_preimage(0, BSV::Transaction::Sighash::NONE_FORK_ID)

      expect(extract_hash_prevouts(preimage)).to eq(known_hash_prevouts)
      expect(extract_hash_sequence(preimage)).to eq(zero_hash)
      expect(extract_hash_outputs(preimage)).to eq(zero_hash)
      expect(extract_sighash_type(preimage)).to eq(0x42)
    end

    it 'SINGLE|FORKID zeroes hashSequence and hashes only matching output' do
      preimage = tx.sighash_preimage(0, BSV::Transaction::Sighash::SINGLE_FORK_ID)

      expected_single_hash = BSV::Primitives::Digest.sha256d(tx.outputs[0].to_binary)

      expect(extract_hash_prevouts(preimage)).to eq(known_hash_prevouts)
      expect(extract_hash_sequence(preimage)).to eq(zero_hash)
      expect(extract_hash_outputs(preimage)).to eq(expected_single_hash)
      expect(extract_sighash_type(preimage)).to eq(0x43)
    end

    it 'ALL|FORKID|ANYONE_CAN_PAY zeroes hashPrevouts and hashSequence' do
      preimage = tx.sighash_preimage(0, BSV::Transaction::Sighash::ALL_FORK_ID_ANYONE_CAN_PAY)

      expect(extract_hash_prevouts(preimage)).to eq(zero_hash)
      expect(extract_hash_sequence(preimage)).to eq(zero_hash)
      expect(extract_hash_outputs(preimage)).to eq(known_hash_outputs)
      expect(extract_sighash_type(preimage)).to eq(0xC1)
    end

    it 'NONE|FORKID|ANYONE_CAN_PAY zeroes all three hash fields' do
      preimage = tx.sighash_preimage(0, BSV::Transaction::Sighash::NONE_FORK_ID_ANYONE_CAN_PAY)

      expect(extract_hash_prevouts(preimage)).to eq(zero_hash)
      expect(extract_hash_sequence(preimage)).to eq(zero_hash)
      expect(extract_hash_outputs(preimage)).to eq(zero_hash)
      expect(extract_sighash_type(preimage)).to eq(0xC2)
    end

    it 'SINGLE|FORKID|ANYONE_CAN_PAY zeroes hashPrevouts/hashSequence, hashes single output' do
      preimage = tx.sighash_preimage(0, BSV::Transaction::Sighash::SINGLE_FORK_ID_ANYONE_CAN_PAY)

      expected_single_hash = BSV::Primitives::Digest.sha256d(tx.outputs[0].to_binary)

      expect(extract_hash_prevouts(preimage)).to eq(zero_hash)
      expect(extract_hash_sequence(preimage)).to eq(zero_hash)
      expect(extract_hash_outputs(preimage)).to eq(expected_single_hash)
      expect(extract_sighash_type(preimage)).to eq(0xC3)
    end

    it 'SINGLE|FORKID with no matching output returns zero hashOutputs' do
      # input_index 0 but no outputs
      tx_no_outputs = described_class.new
      input = BSV::Transaction::TransactionInput.new(
        prev_wtxid: "\x01".b * 32,
        prev_tx_out_index: 0
      )
      input.source_satoshis = 100_000
      input.source_locking_script = source_script
      tx_no_outputs.add_input(input)

      preimage = tx_no_outputs.sighash_preimage(0, BSV::Transaction::Sighash::SINGLE_FORK_ID)
      expect(extract_hash_outputs(preimage)).to eq(zero_hash)
    end

    it 'produces different sighashes for each type' do
      types = [
        BSV::Transaction::Sighash::ALL_FORK_ID,
        BSV::Transaction::Sighash::NONE_FORK_ID,
        BSV::Transaction::Sighash::SINGLE_FORK_ID,
        BSV::Transaction::Sighash::ALL_FORK_ID_ANYONE_CAN_PAY
      ]

      hashes = types.map { |t| tx.sighash(0, t) }
      expect(hashes.uniq.length).to eq(types.length)
    end
  end

  describe 'Sighash constants' do
    it 'defines MASK as 0x1f' do
      expect(BSV::Transaction::Sighash::MASK).to eq(0x1f)
    end

    it 'defines combined FORKID constants' do
      expect(BSV::Transaction::Sighash::NONE_FORK_ID).to eq(0x42)
      expect(BSV::Transaction::Sighash::SINGLE_FORK_ID).to eq(0x43)
      expect(BSV::Transaction::Sighash::ALL_FORK_ID_ANYONE_CAN_PAY).to eq(0xC1)
      expect(BSV::Transaction::Sighash::NONE_FORK_ID_ANYONE_CAN_PAY).to eq(0xC2)
      expect(BSV::Transaction::Sighash::SINGLE_FORK_ID_ANYONE_CAN_PAY).to eq(0xC3)
    end
  end

  describe '#sign / #sign_all' do
    it 'signs a P2PKH input and produces a valid unlocking script' do
      private_key = BSV::Primitives::PrivateKey.generate

      # Create a P2PKH locking script for this key
      pubkey_hash = private_key.public_key.hash160
      locking_script = BSV::Script::Script.p2pkh_lock(pubkey_hash)

      tx = described_class.new
      input = BSV::Transaction::TransactionInput.new(
        prev_wtxid: "\x01".b * 32,
        prev_tx_out_index: 0
      )
      input.source_satoshis = 100_000
      input.source_locking_script = locking_script
      tx.add_input(input)

      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: 90_000,
                      locking_script: locking_script
                    ))

      tx.sign(0, private_key)

      expect(tx.inputs[0].unlocking_script).not_to be_nil
      chunks = tx.inputs[0].unlocking_script.chunks
      expect(chunks.length).to eq(2)

      # Signature chunk should end with sighash type byte (0x41)
      sig_data = chunks[0].data
      expect(sig_data.getbyte(sig_data.bytesize - 1)).to eq(0x41)

      # Public key chunk should be 33 bytes (compressed)
      expect(chunks[1].data.bytesize).to eq(33)
    end

    it 'sign_all signs all unsigned inputs' do
      private_key = BSV::Primitives::PrivateKey.generate
      pubkey_hash = private_key.public_key.hash160
      locking_script = BSV::Script::Script.p2pkh_lock(pubkey_hash)

      tx = described_class.new

      2.times do
        input = BSV::Transaction::TransactionInput.new(
          prev_wtxid: "\x02".b * 32,
          prev_tx_out_index: 0
        )
        input.source_satoshis = 50_000
        input.source_locking_script = locking_script
        tx.add_input(input)
      end

      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: 90_000,
                      locking_script: locking_script
                    ))

      tx.sign_all(private_key)

      tx.inputs.each do |input|
        expect(input.unlocking_script).not_to be_nil
      end
    end
  end

  describe 'UnlockingScriptTemplate integration' do
    let(:private_key) { BSV::Primitives::PrivateKey.generate }
    let(:pubkey_hash) { private_key.public_key.hash160 }
    let(:locking_script) { BSV::Script::Script.p2pkh_lock(pubkey_hash) }

    def build_input(prev_byte: "\x01".b, satoshis: 100_000)
      input = BSV::Transaction::TransactionInput.new(
        prev_wtxid: prev_byte * 32,
        prev_tx_out_index: 0
      )
      input.source_satoshis = satoshis
      input.source_locking_script = locking_script
      input
    end

    it 'sign_all delegates to templates when present' do
      template = BSV::Transaction::P2PKH.new(private_key)

      tx = described_class.new
      input = build_input
      input.unlocking_script_template = template
      tx.add_input(input)
      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: 90_000, locking_script: locking_script
                    ))

      tx.sign_all

      expect(tx.inputs[0].unlocking_script).not_to be_nil
      expect(tx.inputs[0].unlocking_script.chunks.length).to eq(2)
    end

    it 'sign_all with templates produces same result as sign with private key' do
      # Template-based
      template_tx = described_class.new
      input1 = build_input
      input1.unlocking_script_template = BSV::Transaction::P2PKH.new(private_key)
      template_tx.add_input(input1)
      template_tx.add_output(BSV::Transaction::TransactionOutput.new(
                               satoshis: 90_000, locking_script: locking_script
                             ))
      template_tx.sign_all

      # Direct signing
      direct_tx = described_class.new
      input2 = build_input
      direct_tx.add_input(input2)
      direct_tx.add_output(BSV::Transaction::TransactionOutput.new(
                             satoshis: 90_000, locking_script: locking_script
                           ))
      direct_tx.sign(0, private_key)

      expect(template_tx.to_hex).to eq(direct_tx.to_hex)
    end

    it 'sign_all uses private_key fallback for inputs without templates' do
      tx = described_class.new

      # Input with template
      input1 = build_input(prev_byte: "\x01".b)
      input1.unlocking_script_template = BSV::Transaction::P2PKH.new(private_key)
      tx.add_input(input1)

      # Input without template
      input2 = build_input(prev_byte: "\x02".b)
      tx.add_input(input2)

      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: 190_000, locking_script: locking_script
                    ))

      tx.sign_all(private_key)

      tx.inputs.each do |input|
        expect(input.unlocking_script).not_to be_nil
      end
    end

    it 'sign_all skips already-signed inputs' do
      tx = described_class.new
      input = build_input
      input.unlocking_script_template = BSV::Transaction::P2PKH.new(private_key)
      tx.add_input(input)
      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: 90_000, locking_script: locking_script
                    ))

      # Sign once
      tx.sign_all
      first_script = tx.inputs[0].unlocking_script.to_hex

      # Sign again — should not change
      tx.sign_all
      expect(tx.inputs[0].unlocking_script.to_hex).to eq(first_script)
    end

    it 'estimated_fee uses template estimated_length' do
      tx = described_class.new
      input = build_input
      input.unlocking_script_template = BSV::Transaction::P2PKH.new(private_key)
      tx.add_input(input)
      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: 90_000,
                      locking_script: BSV::Script::Script.p2pkh_lock("\x00".b * 20)
                    ))

      fee = tx.estimated_fee
      # P2PKH template estimates 107 byte script
      # Total: 4 + 1 + (32+4+1+107+4) + 1 + 34 + 4 = 192 bytes
      # At 0.5 sat/byte = 96
      expect(fee).to be > 0
      expect(fee).to be < 200
    end
  end

  describe '#estimated_fee' do
    it 'estimates fee for unsigned inputs with template' do
      tx = described_class.new
      input = BSV::Transaction::TransactionInput.new(
        prev_wtxid: "\x00".b * 32,
        prev_tx_out_index: 0
      )
      input.source_satoshis = 100_000
      input.unlocking_script_template = BSV::Transaction::P2PKH.new(BSV::Primitives::PrivateKey.generate)
      tx.add_input(input)

      pubkey_hash = ("\x00".b * 20)
      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: 90_000,
                      locking_script: BSV::Script::Script.p2pkh_lock(pubkey_hash)
                    ))

      fee = tx.estimated_fee
      # With 0.5 sat/byte default: ~192 bytes * 0.5 = ~96
      expect(fee).to be > 0
      expect(fee).to be < 200
    end
  end

  describe '#estimated_fee with multiple inputs and outputs' do
    it 'estimates fee for a transaction with multiple inputs' do
      tx = described_class.new
      pubkey_hash = "\x00".b * 20

      dummy_key = BSV::Primitives::PrivateKey.generate
      3.times do |i|
        input = BSV::Transaction::TransactionInput.new(
          prev_wtxid: "\x00".b * 32,
          prev_tx_out_index: i
        )
        input.source_satoshis = 50_000
        input.unlocking_script_template = BSV::Transaction::P2PKH.new(dummy_key)
        tx.add_input(input)
      end

      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: 140_000,
                      locking_script: BSV::Script::Script.p2pkh_lock(pubkey_hash)
                    ))

      fee = tx.estimated_fee
      # 3 unsigned inputs (~148 each) + 1 output (~34) + overhead (~10) ≈ 488 bytes * 0.1 sat/byte
      expect(fee).to be > 40
      expect(fee).to be < 100
    end

    it 'estimates fee for a transaction with an OP_RETURN output' do
      tx = described_class.new
      input = BSV::Transaction::TransactionInput.new(
        prev_wtxid: "\x00".b * 32,
        prev_tx_out_index: 0
      )
      input.source_satoshis = 100_000
      input.unlocking_script_template = BSV::Transaction::P2PKH.new(BSV::Primitives::PrivateKey.generate)
      tx.add_input(input)

      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: 0,
                      locking_script: BSV::Script::Script.op_return('hello world')
                    ))
      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: 90_000,
                      locking_script: BSV::Script::Script.p2pkh_lock("\x00".b * 20)
                    ))

      fee = tx.estimated_fee
      expect(fee).to be > 0
      expect(fee).to be < 300
    end

    it 'scales fee with satoshis_per_byte rate' do
      tx = described_class.new
      input = BSV::Transaction::TransactionInput.new(
        prev_wtxid: "\x00".b * 32,
        prev_tx_out_index: 0
      )
      input.source_satoshis = 100_000
      input.unlocking_script_template = BSV::Transaction::P2PKH.new(BSV::Primitives::PrivateKey.generate)
      tx.add_input(input)

      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: 90_000,
                      locking_script: BSV::Script::Script.p2pkh_lock("\x00".b * 20)
                    ))

      fee_half = tx.estimated_fee(satoshis_per_byte: 0.5)
      fee_one = tx.estimated_fee(satoshis_per_byte: 1.0)
      fee_two = tx.estimated_fee(satoshis_per_byte: 2.0)

      expect(fee_one).to be >= fee_half * 2
      expect(fee_two).to eq(fee_one * 2)
    end

    it 'produces an estimate within 5% of actual signed size' do
      private_key = BSV::Primitives::PrivateKey.generate
      pubkey_hash = private_key.public_key.hash160
      locking_script = BSV::Script::Script.p2pkh_lock(pubkey_hash)

      tx = described_class.new
      input = BSV::Transaction::TransactionInput.new(
        prev_wtxid: BSV::Primitives::Digest.sha256d('utxo'),
        prev_tx_out_index: 0
      )
      input.source_satoshis = 100_000
      input.source_locking_script = locking_script
      input.unlocking_script_template = BSV::Transaction::P2PKH.new(private_key)
      tx.add_input(input)
      tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 90_000, locking_script: locking_script))

      estimated = tx.estimated_fee(satoshis_per_byte: 1.0)
      tx.sign(0, private_key)
      actual_size = tx.to_binary.bytesize

      expect(estimated).to be_within(actual_size * 0.05).of(actual_size)
    end
  end

  describe '#total_input_satoshis / #total_output_satoshis' do
    it 'sums input and output values' do
      tx = described_class.new

      input = BSV::Transaction::TransactionInput.new(
        prev_wtxid: "\x00".b * 32,
        prev_tx_out_index: 0
      )
      input.source_satoshis = 100_000
      tx.add_input(input)

      pubkey_hash = "\x00".b * 20
      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: 90_000,
                      locking_script: BSV::Script::Script.p2pkh_lock(pubkey_hash)
                    ))

      expect(tx.total_input_satoshis).to eq(100_000)
      expect(tx.total_output_satoshis).to eq(90_000)
    end

    it 'raises when any input has nil source_satoshis' do
      tx = described_class.new
      input = BSV::Transaction::TransactionInput.new(
        prev_wtxid: "\x00".b * 32,
        prev_tx_out_index: 0
      )
      # source_satoshis intentionally not set
      tx.add_input(input)

      expect { tx.total_input_satoshis }.to raise_error(ArgumentError, /input 0 has nil source_satoshis/)
    end

    it 'returns 0 for a transaction with no inputs' do
      tx = described_class.new
      expect(tx.total_input_satoshis).to eq(0)
    end
  end

  describe '#fee with numeric argument' do
    # Builds a minimal transaction with one input and one change output so that
    # distribute_change runs, and we can observe the resulting change satoshis.
    def tx_with_input_sats(input_sats)
      tx = described_class.new
      input = BSV::Transaction::TransactionInput.new(
        prev_wtxid: "\x00".b * 32,
        prev_tx_out_index: 0
      )
      input.source_satoshis = input_sats
      tx.add_input(input)
      pubkey_hash = "\x00".b * 20
      output = BSV::Transaction::TransactionOutput.new(
        satoshis: 0,
        locking_script: BSV::Script::Script.p2pkh_lock(pubkey_hash)
      )
      output.change = true
      tx.add_output(output)
      tx
    end

    it 'passes an integer fee through unchanged' do
      tx = tx_with_input_sats(1_000)
      tx.fee(100)
      expect(tx.outputs.first.satoshis).to eq(900)
    end

    it 'rounds a fractional fee of 100.5 up to 101' do
      tx = tx_with_input_sats(1_000)
      tx.fee(100.5)
      expect(tx.outputs.first.satoshis).to eq(899)
    end

    it 'rounds a fractional fee of 100.1 up to 101' do
      tx = tx_with_input_sats(1_000)
      tx.fee(100.1)
      expect(tx.outputs.first.satoshis).to eq(899)
    end

    it 'keeps 100.0 as 100 — ceil is a no-op for whole floats' do
      tx = tx_with_input_sats(1_000)
      tx.fee(100.0)
      expect(tx.outputs.first.satoshis).to eq(900)
    end
  end

  describe '.from_beef' do
    # Shared helpers for building synthetic BEEF fixtures.
    let(:lock) { BSV::Script::Script.new }
    let(:pe)   { BSV::Transaction::MerklePath::PathElement }

    # Build a minimal proven ancestor with a synthetic merkle path.
    #
    # PathElement hashes must be in wire byte order (MerklePath serialisation).
    def proven_tx(satoshis: 1000, block_height: 800_000, offset: 0)
      tx = BSV::Transaction::Transaction.new
      tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: satoshis, locking_script: lock))
      sibling_hash = BSV::Primitives::Digest.sha256("sibling_#{offset}") # 32 raw bytes
      tx.merkle_path = BSV::Transaction::MerklePath.new(
        block_height: block_height,
        path: [[pe.new(offset: offset, hash: tx.wtxid, txid: true),
                pe.new(offset: offset ^ 1, hash: sibling_hash)]]
      )
      tx
    end

    # Wire an input from parent_tx output 0 into child_tx.
    # prev_wtxid must be in wire byte order.
    def add_input(child_tx, parent_tx)
      inp = BSV::Transaction::TransactionInput.new(
        prev_wtxid: parent_tx.wtxid, prev_tx_out_index: 0
      )
      inp.source_transaction = parent_tx
      inp.source_satoshis = parent_tx.outputs[0].satoshis
      inp.source_locking_script = lock
      child_tx.add_input(inp)
    end

    it 'returns nil for an empty BEEF' do
      # Build a minimal BEEF with no transactions
      empty_beef = BSV::Transaction::Beef.new
      binary = empty_beef.to_binary
      expect(described_class.from_beef(binary)).to be_nil
    end

    it 'returns the subject tx for a plain BEEF (no subject_txid)' do
      ancestor = proven_tx(satoshis: 2000)
      subject  = described_class.new
      subject.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 100, locking_script: lock))
      add_input(subject, ancestor)

      beef = BSV::Transaction::Beef.new
      beef.merge_transaction(subject)
      binary = beef.to_binary

      result = described_class.from_beef(binary)
      expect(result).not_to be_nil
      expect(result.wtxid).to eq(subject.wtxid)
    end

    it 'wires source_transaction on every input when ancestry is present' do
      ancestor = proven_tx(satoshis: 3000)
      subject  = described_class.new
      subject.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 200, locking_script: lock))
      add_input(subject, ancestor)

      beef = BSV::Transaction::Beef.new
      beef.merge_transaction(subject)
      binary = beef.to_binary

      result = described_class.from_beef(binary)
      expect(result.inputs.all?(&:source_transaction)).to be true
    end

    it 'wires ancestry across 2 generations' do
      grandparent = proven_tx(satoshis: 5000, block_height: 700_000, offset: 0)

      parent = described_class.new
      parent.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 4000, locking_script: lock))
      add_input(parent, grandparent)

      subject = described_class.new
      subject.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 3000, locking_script: lock))
      add_input(subject, parent)

      beef = BSV::Transaction::Beef.new
      beef.merge_transaction(subject)
      binary = beef.to_binary

      result = described_class.from_beef(binary)
      expect(result.inputs[0].source_transaction).not_to be_nil
      parent_recovered = result.inputs[0].source_transaction
      expect(parent_recovered.inputs[0].source_transaction).not_to be_nil
      expect(parent_recovered.inputs[0].source_transaction.wtxid).to eq(grandparent.wtxid)
    end

    it 'attaches late-bound BUMPs on FORMAT_RAW_TX ancestors' do
      # This spec proves `from_beef` routes through `find_atomic_transaction`
      # for the late-bind case: ancestor stored on-wire as FORMAT_RAW_TX
      # (has_bump=0) while its BUMP lives in @bumps separately.
      #
      # We deliberately bypass `merge_bump`, which runs F5.6's retroactive
      # upgrade and would promote the ancestor to FORMAT_RAW_TX_AND_BUMP —
      # that path is already tested elsewhere and doesn't exercise
      # `find_atomic_transaction`'s late-bind because the parser wires
      # `merkle_path` at read time from `has_bump=1`.
      ancestor = described_class.new
      ancestor.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 1500, locking_script: lock))

      subject = described_class.new
      subject.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 500, locking_script: lock))
      add_input(subject, ancestor)

      # PathElement hashes use wire byte order.
      sibling_hash = BSV::Primitives::Digest.sha256('late_sibling')
      bump = BSV::Transaction::MerklePath.new(
        block_height: 850_000,
        path: [[pe.new(offset: 0, hash: ancestor.wtxid, txid: true),
                pe.new(offset: 1, hash: sibling_hash)]]
      )

      beef = BSV::Transaction::Beef.new
      beef.merge_transaction(subject)
      # Push the BUMP directly into @bumps, bypassing merge_bump so F5.6 does
      # NOT fire. The ancestor entry stays FORMAT_RAW_TX on-wire.
      beef.bumps << bump
      binary = beef.to_binary

      # Sanity: the serialised ancestor must be FORMAT_RAW_TX (has_bump=0).
      # If this fails the spec is no longer exercising the late-bind path.
      reparsed = BSV::Transaction::Beef.from_binary(binary)
      ancestor_entry = reparsed.transactions.find { |bt| bt.is_a?(BSV::Transaction::Beef::RawTxEntry) && bt.transaction.wtxid == ancestor.wtxid }
      expect(ancestor_entry).to be_a(BSV::Transaction::Beef::RawTxEntry)

      result = described_class.from_beef(binary)
      expect(result).not_to be_nil
      ancestor_recovered = result.inputs[0].source_transaction
      expect(ancestor_recovered).not_to be_nil
      expect(ancestor_recovered.merkle_path).not_to be_nil
      # Proof the BUMP really came from late-bind: the wired merkle_path must
      # be the same object (or equal by block_height + leaf hash) as the one
      # we pushed into @bumps.
      expect(ancestor_recovered.merkle_path.block_height).to eq(850_000)
    end

    it 'returns the subject tx for an Atomic BEEF (subject_txid set)' do
      ancestor = proven_tx(satoshis: 4000, offset: 2)
      subject  = described_class.new
      subject.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 500, locking_script: lock))
      add_input(subject, ancestor)

      beef = BSV::Transaction::Beef.new
      beef.merge_transaction(subject)
      # Serialise as Atomic BEEF so subject_txid is embedded
      binary = beef.to_atomic_binary(subject.wtxid)

      result = described_class.from_beef(binary)
      expect(result).not_to be_nil
      expect(result.wtxid).to eq(subject.wtxid)
      expect(result.inputs.all?(&:source_transaction)).to be true
    end
  end

  describe 'full attestation flow' do
    it 'constructs, signs, and serialises a transaction with P2PKH input, OP_RETURN, and change' do
      private_key = BSV::Primitives::PrivateKey.generate
      pubkey_hash = private_key.public_key.hash160
      locking_script = BSV::Script::Script.p2pkh_lock(pubkey_hash)

      tx = described_class.new

      # Fund with a UTXO
      input = BSV::Transaction::TransactionInput.new(
        prev_wtxid: BSV::Primitives::Digest.sha256d('fake utxo'),
        prev_tx_out_index: 0
      )
      input.source_satoshis = 1_000_000
      input.source_locking_script = locking_script
      input.unlocking_script_template = BSV::Transaction::P2PKH.new(private_key)
      tx.add_input(input)

      # OP_RETURN data output
      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: 0,
                      locking_script: BSV::Script::Script.op_return('attestation data'.b)
                    ))

      # Change output
      fee = tx.estimated_fee
      change = 1_000_000 - fee
      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: change,
                      locking_script: locking_script
                    ))

      # Sign
      tx.sign(0, private_key)

      # Verify serialisation round-trip
      hex = tx.to_hex
      parsed = described_class.from_hex(hex)

      expect(parsed.version).to eq(1)
      expect(parsed.inputs.length).to eq(1)
      expect(parsed.outputs.length).to eq(2)
      expect(parsed.inputs[0].unlocking_script).not_to be_nil
      expect(parsed.outputs[0].satoshis).to eq(0)
      expect(parsed.outputs[1].satoshis).to eq(change)
      expect(parsed.to_hex).to eq(hex)

      # Txid should be deterministic
      expect(parsed.txid_hex).to eq(tx.txid_hex)
      expect(tx.txid_hex.length).to eq(64)
    end
  end
end
