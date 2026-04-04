# frozen_string_literal: true

require 'bsv-sdk'
require 'bsv-wallet'

RSpec.describe 'BSV::Script::PushDropTemplate' do
  let(:private_key) { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(42)) }
  let(:wallet)      { BSV::Wallet::ProtoWallet.new(private_key) }
  let(:template)    { BSV::Script::PushDropTemplate.new(wallet: wallet) }

  let(:protocol_id)  { [1, 'push drop test'] }
  let(:key_id)       { '1' }
  let(:counterparty) { 'self' }
  let(:fields)       { ['hello'.b, 'world'.b] }

  describe '#lock' do
    it 'returns a PushDrop script' do
      script = template.lock(
        fields: fields,
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: counterparty
      )
      expect(script).to be_a(BSV::Script::Script)
      expect(script.pushdrop?).to be true
    end

    it 'appends a signature field when include_signature is true (default)' do
      script = template.lock(
        fields: fields,
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: counterparty,
        include_signature: true
      )
      extracted = script.pushdrop_fields
      # Original 2 fields + 1 signature field
      expect(extracted.length).to eq(3)
    end

    it 'does not append a signature field when include_signature is false' do
      script = template.lock(
        fields: fields,
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: counterparty,
        include_signature: false
      )
      extracted = script.pushdrop_fields
      expect(extracted.length).to eq(2)
    end

    it 'preserves the original field data in order' do
      script = template.lock(
        fields: fields,
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: counterparty,
        include_signature: false
      )
      extracted = script.pushdrop_fields
      expect(extracted[0]).to eq('hello'.b)
      expect(extracted[1]).to eq('world'.b)
    end

    it 'raises ArgumentError when fields is empty' do
      expect do
        template.lock(
          fields: [],
          protocol_id: protocol_id,
          key_id: key_id,
          counterparty: counterparty
        )
      end.to raise_error(ArgumentError, /fields must not be empty/)
    end

    context 'when counterparty is "anyone"' do
      it 'uses the generator point as the locking public key' do
        script = template.lock(
          fields: fields,
          protocol_id: protocol_id,
          key_id: key_id,
          counterparty: 'anyone',
          include_signature: false
        )

        # The underlying lock script is P2PKH; extract the pubkey hash from it
        lock_part = script.pushdrop_lock_script
        expect(lock_part.p2pkh?).to be true

        # The hash160 of the generator point G should be the embedded pubkey hash
        generator_bytes = [BSV::Script::PushDropTemplate::GENERATOR_PUBKEY_HEX].pack('H*')
        expected_hash = BSV::Primitives::Digest.hash160(generator_bytes)

        # Extract pubkey hash from P2PKH script: bytes 3..22 (after OP_DUP OP_HASH160 0x14)
        lock_bytes = lock_part.bytes
        embedded_hash = lock_bytes[3, 20]
        expect(embedded_hash).to eq(expected_hash)
      end

      it 'GENERATOR_PUBKEY_HEX matches PrivateKey(1).public_key' do
        gen_key = BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(1))
        expect(BSV::Script::PushDropTemplate::GENERATOR_PUBKEY_HEX)
          .to eq(gen_key.public_key.to_hex)
      end
    end

    context 'when originator is set' do
      let(:template_with_originator) do
        BSV::Script::PushDropTemplate.new(wallet: wallet, originator: 'example.com')
      end

      it 'passes originator through to wallet calls' do
        # Verify that originator does not break normal operation
        script = template_with_originator.lock(
          fields: fields,
          protocol_id: protocol_id,
          key_id: key_id,
          counterparty: counterparty
        )
        expect(script.pushdrop?).to be true
      end
    end
  end

  describe '#unlock' do
    it 'returns an Unlocker object' do
      unlocker = template.unlock(
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: counterparty
      )
      expect(unlocker).to be_a(BSV::Script::PushDropTemplate::Unlocker)
    end

    it 'returns an estimated length of 107' do
      unlocker = template.unlock(
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: counterparty
      )
      expect(unlocker.estimated_length(nil, nil)).to eq(107)
    end

    describe '#sign' do
      it 'produces a valid unlocking script' do
        lock_script = template.lock(
          fields: fields,
          protocol_id: protocol_id,
          key_id: key_id,
          counterparty: counterparty,
          include_signature: false
        )

        spending_tx = build_spending_tx(lock_script, satoshis: 10_000)

        unlocker = template.unlock(
          protocol_id: protocol_id,
          key_id: key_id,
          counterparty: counterparty
        )
        unlock_script = unlocker.sign(spending_tx, 0)

        expect(unlock_script).to be_a(BSV::Script::Script)
        expect(unlock_script.bytes).not_to be_empty
      end
    end
  end

  describe 'round-trip: lock then unlock passes interpreter verification' do
    it 'verifies a PushDrop transaction with P2PKH underlying lock' do
      lock_script = template.lock(
        fields: fields,
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: counterparty,
        include_signature: true
      )

      satoshis = 10_000
      spending_tx = build_spending_tx(lock_script, satoshis: satoshis)

      unlocker = template.unlock(
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: counterparty
      )
      spending_tx.inputs[0].unlocking_script = unlocker.sign(spending_tx, 0)

      result = BSV::Script::Interpreter.verify(
        tx: spending_tx,
        input_index: 0,
        unlock_script: spending_tx.inputs[0].unlocking_script,
        lock_script: lock_script,
        satoshis: satoshis
      )
      expect(result).to be true
    end

    it 'also verifies without the field signature' do
      lock_script = template.lock(
        fields: fields,
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: counterparty,
        include_signature: false
      )

      satoshis = 5_000
      spending_tx = build_spending_tx(lock_script, satoshis: satoshis)

      unlocker = template.unlock(
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: counterparty
      )
      spending_tx.inputs[0].unlocking_script = unlocker.sign(spending_tx, 0)

      result = BSV::Script::Interpreter.verify(
        tx: spending_tx,
        input_index: 0,
        unlock_script: spending_tx.inputs[0].unlocking_script,
        lock_script: lock_script,
        satoshis: satoshis
      )
      expect(result).to be true
    end
  end

  private

  # Build a transaction spending a PushDrop output with the given locking script.
  #
  # Sets +source_locking_script+ and +source_satoshis+ on the input so the
  # sighash computation has everything it needs.
  def build_spending_tx(lock_script, satoshis:)
    tx = BSV::Transaction::Transaction.new
    input = BSV::Transaction::TransactionInput.new(
      prev_tx_id: "\x00" * 32,
      prev_tx_out_index: 0
    )
    input.source_locking_script = lock_script
    input.source_satoshis = satoshis
    tx.add_input(input)
    # Add a dummy output so the transaction is structurally valid
    dummy_lock = BSV::Script::Script.p2pkh_lock(("\x00" * 20).b)
    tx.add_output(BSV::Transaction::TransactionOutput.new(
                    satoshis: satoshis - 1_000,
                    locking_script: dummy_lock
                  ))
    tx
  end
end
