# frozen_string_literal: true

RSpec.describe BSV::Transaction::P2PKH do
  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  let(:pubkey_hash) { private_key.public_key.hash160 }
  let(:locking_script) { BSV::Script::Script.p2pkh_lock(pubkey_hash) }

  let(:tx) do
    tx = BSV::Transaction::Transaction.new
    input = BSV::Transaction::TransactionInput.new(
      prev_tx_id: "\x01".b * 32,
      prev_tx_out_index: 0
    )
    input.source_satoshis = 100_000
    input.source_locking_script = locking_script
    tx.add_input(input)
    tx.add_output(BSV::Transaction::TransactionOutput.new(
                    satoshis: 90_000,
                    locking_script: locking_script
                  ))
    tx
  end

  describe '#sign' do
    it 'produces a valid P2PKH unlocking script' do
      template = described_class.new(private_key)
      script = template.sign(tx, 0)

      chunks = script.chunks
      expect(chunks.length).to eq(2)

      # Signature ends with sighash type byte (0x41 = ALL|FORKID)
      sig_data = chunks[0].data
      expect(sig_data.getbyte(sig_data.bytesize - 1)).to eq(0x41)

      # Public key is 33 bytes (compressed)
      expect(chunks[1].data.bytesize).to eq(33)
    end

    it 'produces the same result as Transaction#sign' do
      # Sign with direct method
      direct_tx = BSV::Transaction::Transaction.new
      input1 = BSV::Transaction::TransactionInput.new(
        prev_tx_id: "\x01".b * 32,
        prev_tx_out_index: 0
      )
      input1.source_satoshis = 100_000
      input1.source_locking_script = locking_script
      direct_tx.add_input(input1)
      direct_tx.add_output(BSV::Transaction::TransactionOutput.new(
                             satoshis: 90_000,
                             locking_script: locking_script
                           ))
      direct_tx.sign(0, private_key)

      # Sign with template
      template = described_class.new(private_key)
      script = template.sign(tx, 0)

      # Both should produce identical unlocking scripts
      expect(script.to_hex).to eq(direct_tx.inputs[0].unlocking_script.to_hex)
    end

    it 'uses a custom sighash type when specified' do
      template = described_class.new(private_key, sighash_type: BSV::Transaction::Sighash::NONE_FORK_ID)
      script = template.sign(tx, 0)

      sig_data = script.chunks[0].data
      expect(sig_data.getbyte(sig_data.bytesize - 1)).to eq(0x42)
    end
  end

  describe '#estimated_length' do
    it 'returns 107' do
      template = described_class.new(private_key)
      expect(template.estimated_length(tx, 0)).to eq(107)
    end
  end
end
