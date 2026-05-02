# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Transaction::Transaction do
  describe 'Extended Format (EF) serialisation' do
    # Go SDK test vector — a signed P2PKH transaction with 1 input, 1 output
    let(:go_sdk_ef_hex) do
      '010000000000000000ef01' \
        'ac4e164f5bc16746bb0868404292ac8318bbac3800e4aad13a014da427adce3e' \
        '000000006a' \
        '47304402203a61a2e931612b4bda08d541cfb980885173b8dcf64a3471238ae7abcd368d64' \
        '02204cbf24f04b9aa2256d8901f0ed97866603d2be8324c2bfb7a37bf8fc90edd5b4' \
        '41210263e2dee22b1ddc5e11f6fab8bcd2378bdd19580d640501ea956ec0e786f93e76' \
        'ffffffff' \
        '3e66000000000000' \
        '1976a9146bfd5c7fbe21529d45803dbcf0c87dd3c71efbc288ac' \
        '01' \
        '3c66000000000000' \
        '1976a9146bfd5c7fbe21529d45803dbcf0c87dd3c71efbc288ac' \
        '00000000'
    end

    describe '#to_ef' do
      it 'serialises a transaction with EF marker and source data' do
        priv = BSV::Primitives::PrivateKey.generate
        pub = priv.public_key
        lock_script = BSV::Script::Script.p2pkh_lock(pub.hash160)

        tx = described_class.new
        input = BSV::Transaction::TransactionInput.new(
          prev_wtxid: "\x01".b * 32,
          prev_tx_out_index: 0
        )
        input.source_satoshis = 50_000
        input.source_locking_script = lock_script
        tx.add_input(input)
        tx.add_output(BSV::Transaction::TransactionOutput.new(
                        satoshis: 49_000,
                        locking_script: lock_script
                      ))
        tx.sign(0, priv)

        ef = tx.to_ef

        # EF marker at bytes 4-9
        expect(ef.byteslice(4, 6)).to eq("\x00\x00\x00\x00\x00\xEF".b)

        # EF is longer than standard (includes source satoshis + locking script per input)
        expect(ef.bytesize).to be > tx.to_binary.bytesize
      end

      it 'raises when source_satoshis and source_locking_script both absent and no source_transaction' do
        tx = described_class.new
        input = BSV::Transaction::TransactionInput.new(
          prev_wtxid: "\x01".b * 32,
          prev_tx_out_index: 0
        )
        tx.add_input(input)

        expect { tx.to_ef }.to raise_error(ArgumentError, /source_satoshis.*source_locking_script|no wired source_transaction/)
      end

      it 'raises when source_locking_script absent and no source_transaction' do
        tx = described_class.new
        input = BSV::Transaction::TransactionInput.new(
          prev_wtxid: "\x01".b * 32,
          prev_tx_out_index: 0
        )
        input.source_satoshis = 1000
        tx.add_input(input)

        expect { tx.to_ef }.to raise_error(ArgumentError, /source_locking_script.*no wired source_transaction/)
      end

      it 'derives source_satoshis from wired source_transaction when only source_locking_script is explicit' do
        priv = BSV::Primitives::PrivateKey.generate
        lock_script = BSV::Script::Script.p2pkh_lock(priv.public_key.hash160)

        source_tx = described_class.new
        source_tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 75_000, locking_script: lock_script))

        # Build unlocking script with full explicit fields, then strip source_satoshis
        prep_tx = described_class.new
        prep_input = BSV::Transaction::TransactionInput.new(
          prev_wtxid: "\x02".b * 32,
          prev_tx_out_index: 0
        )
        prep_input.source_satoshis = 75_000
        prep_input.source_locking_script = lock_script
        prep_tx.add_input(prep_input)
        prep_tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 74_000, locking_script: lock_script))
        prep_tx.sign(0, priv)

        tx = described_class.new
        input = BSV::Transaction::TransactionInput.new(
          prev_wtxid: "\x02".b * 32,
          prev_tx_out_index: 0
        )
        input.unlocking_script = prep_tx.inputs[0].unlocking_script
        input.source_transaction = source_tx
        # source_locking_script explicit, source_satoshis nil — to_ef derives satoshis
        input.source_locking_script = lock_script
        tx.add_input(input)
        tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 74_000, locking_script: lock_script))

        ef = tx.to_ef
        expect(ef.byteslice(4, 6)).to eq("\x00\x00\x00\x00\x00\xEF".b)

        restored = described_class.from_ef(ef)
        expect(restored.inputs[0].source_satoshis).to eq(75_000)
        expect(restored.inputs[0].source_locking_script.to_hex).to eq(lock_script.to_hex)
      end

      it 'derives both source fields from source_transaction when input has a pre-built unlocking_script' do
        priv = BSV::Primitives::PrivateKey.generate
        lock_script = BSV::Script::Script.p2pkh_lock(priv.public_key.hash160)

        source_tx = described_class.new
        source_tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 75_000, locking_script: lock_script))

        # Build and sign a tx with explicit fields, then strip them to simulate a BEEF-parsed input
        prep_tx = described_class.new
        prep_input = BSV::Transaction::TransactionInput.new(
          prev_wtxid: "\x05".b * 32,
          prev_tx_out_index: 0
        )
        prep_input.source_satoshis = 75_000
        prep_input.source_locking_script = lock_script
        prep_tx.add_input(prep_input)
        prep_tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 74_000, locking_script: lock_script))
        prep_tx.sign(0, priv)

        # Simulate BEEF-parsed input: has unlocking_script + source_transaction, no explicit source fields
        tx = described_class.new
        input = BSV::Transaction::TransactionInput.new(
          prev_wtxid: "\x05".b * 32,
          prev_tx_out_index: 0
        )
        input.unlocking_script = prep_tx.inputs[0].unlocking_script
        input.source_transaction = source_tx
        tx.add_input(input)
        tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 74_000, locking_script: lock_script))

        ef = tx.to_ef
        expect(ef.byteslice(4, 6)).to eq("\x00\x00\x00\x00\x00\xEF".b)

        restored = described_class.from_ef(ef)
        expect(restored.inputs[0].source_satoshis).to eq(75_000)
        expect(restored.inputs[0].source_locking_script.to_hex).to eq(lock_script.to_hex)
      end

      it 'does not mutate input when deriving from source_transaction' do
        priv = BSV::Primitives::PrivateKey.generate
        lock_script = BSV::Script::Script.p2pkh_lock(priv.public_key.hash160)

        source_tx = described_class.new
        source_tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 50_000, locking_script: lock_script))

        # Build unlocking script using a separate signed tx
        prep_tx = described_class.new
        prep_input = BSV::Transaction::TransactionInput.new(
          prev_wtxid: "\x03".b * 32,
          prev_tx_out_index: 0
        )
        prep_input.source_satoshis = 50_000
        prep_input.source_locking_script = lock_script
        prep_tx.add_input(prep_input)
        prep_tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 49_000, locking_script: lock_script))
        prep_tx.sign(0, priv)

        tx = described_class.new
        input = BSV::Transaction::TransactionInput.new(
          prev_wtxid: "\x03".b * 32,
          prev_tx_out_index: 0
        )
        input.unlocking_script = prep_tx.inputs[0].unlocking_script
        input.source_transaction = source_tx
        tx.add_input(input)
        tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 49_000, locking_script: lock_script))

        ef1 = tx.to_ef
        expect(input.source_satoshis).to be_nil
        expect(input.source_locking_script).to be_nil

        ef2 = tx.to_ef
        expect(ef1).to eq(ef2)
      end

      it 'handles mixed inputs: some with explicit fields, some derived from source_transaction' do
        priv = BSV::Primitives::PrivateKey.generate
        lock_script = BSV::Script::Script.p2pkh_lock(priv.public_key.hash160)

        source_tx = described_class.new
        source_tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 30_000, locking_script: lock_script))

        # Prepare a signed unlocking script for input1
        prep_tx = described_class.new
        prep_input = BSV::Transaction::TransactionInput.new(
          prev_wtxid: "\x02".b * 32,
          prev_tx_out_index: 0
        )
        prep_input.source_satoshis = 30_000
        prep_input.source_locking_script = lock_script
        prep_tx.add_input(prep_input)
        prep_tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 29_000, locking_script: lock_script))
        prep_tx.sign(0, priv)

        tx = described_class.new

        # Input 0: explicit fields
        input0 = BSV::Transaction::TransactionInput.new(prev_wtxid: "\x01".b * 32, prev_tx_out_index: 0)
        input0.source_satoshis = 20_000
        input0.source_locking_script = lock_script
        input0.unlocking_script_template = BSV::Transaction::P2PKH.new(priv)
        tx.add_input(input0)

        # Input 1: only source_transaction (no explicit source_satoshis / source_locking_script)
        input1 = BSV::Transaction::TransactionInput.new(prev_wtxid: "\x02".b * 32, prev_tx_out_index: 0)
        input1.source_transaction = source_tx
        input1.unlocking_script = prep_tx.inputs[0].unlocking_script
        tx.add_input(input1)

        tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 49_000, locking_script: lock_script))
        tx.sign_all

        ef = tx.to_ef
        restored = described_class.from_ef(ef)

        expect(restored.inputs[0].source_satoshis).to eq(20_000)
        expect(restored.inputs[1].source_satoshis).to eq(30_000)
        expect(restored.inputs[1].source_locking_script.to_hex).to eq(lock_script.to_hex)
      end

      it 'raises when source_output_index is out of range' do
        priv = BSV::Primitives::PrivateKey.generate
        lock_script = BSV::Script::Script.p2pkh_lock(priv.public_key.hash160)

        source_tx = described_class.new
        source_tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 10_000, locking_script: lock_script))

        tx = described_class.new
        input = BSV::Transaction::TransactionInput.new(
          prev_wtxid: "\x04".b * 32,
          prev_tx_out_index: 99 # out of range
        )
        input.source_transaction = source_tx
        tx.add_input(input)

        expect { tx.to_ef }.to raise_error(ArgumentError, /no output at index 99/)
      end
    end

    describe '#to_ef_hex' do
      it 'returns hex-encoded EF' do
        priv = BSV::Primitives::PrivateKey.generate
        pub = priv.public_key
        lock_script = BSV::Script::Script.p2pkh_lock(pub.hash160)

        tx = described_class.new
        input = BSV::Transaction::TransactionInput.new(
          prev_wtxid: "\x01".b * 32,
          prev_tx_out_index: 0
        )
        input.source_satoshis = 50_000
        input.source_locking_script = lock_script
        tx.add_input(input)
        tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 49_000, locking_script: lock_script))
        tx.sign(0, priv)

        expect(tx.to_ef_hex).to eq(tx.to_ef.unpack1('H*'))
      end
    end

    describe '.from_ef' do
      it 'parses the Go SDK test vector correctly' do
        tx = described_class.from_ef_hex(go_sdk_ef_hex)

        expect(tx.version).to eq(1)
        expect(tx.inputs.length).to eq(1)
        expect(tx.outputs.length).to eq(1)
        expect(tx.lock_time).to eq(0)

        input = tx.inputs[0]
        expect(input.source_satoshis).to eq(26_174)
        expect(input.source_locking_script).not_to be_nil
        expect(input.source_locking_script.type).to eq('pubkeyhash')
        expect(input.source_locking_script.to_hex).to eq(
          '76a9146bfd5c7fbe21529d45803dbcf0c87dd3c71efbc288ac'
        )
        expect(input.unlocking_script).not_to be_nil

        output = tx.outputs[0]
        expect(output.satoshis).to eq(26_172)
      end

      it 'raises on invalid EF marker' do
        bad_data = "\x01\x00\x00\x00\x01\x02\x03\x04\x05\x06".b
        expect { described_class.from_ef(bad_data) }.to raise_error(ArgumentError, /EF marker/)
      end
    end

    describe '.from_ef_hex' do
      it 'parses hex-encoded EF' do
        tx = described_class.from_ef_hex(go_sdk_ef_hex)
        expect(tx.inputs.length).to eq(1)
        expect(tx.inputs[0].source_satoshis).to eq(26_174)
      end
    end

    describe 'round-trip' do
      it 'Go SDK vector round-trips exactly' do
        tx = described_class.from_ef_hex(go_sdk_ef_hex)
        expect(tx.to_ef_hex).to eq(go_sdk_ef_hex)
      end

      it 'round-trips a freshly built and signed transaction' do
        priv = BSV::Primitives::PrivateKey.generate
        pub = priv.public_key
        lock_script = BSV::Script::Script.p2pkh_lock(pub.hash160)

        tx = described_class.new
        input = BSV::Transaction::TransactionInput.new(
          prev_wtxid: BSV::Primitives::Digest.sha256d('test source tx'),
          prev_tx_out_index: 0
        )
        input.source_satoshis = 100_000
        input.source_locking_script = lock_script
        tx.add_input(input)
        tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 99_000, locking_script: lock_script))
        tx.sign(0, priv)

        roundtrip = described_class.from_ef(tx.to_ef)

        expect(roundtrip.txid_hex).to eq(tx.txid_hex)
        expect(roundtrip.inputs[0].source_satoshis).to eq(100_000)
        expect(roundtrip.inputs[0].source_locking_script.to_hex).to eq(lock_script.to_hex)
        expect(roundtrip.to_ef_hex).to eq(tx.to_ef_hex)
      end

      it 'round-trips a multi-input transaction' do
        priv = BSV::Primitives::PrivateKey.generate
        pub = priv.public_key
        lock_script = BSV::Script::Script.p2pkh_lock(pub.hash160)

        tx = described_class.new
        3.times do |i|
          input = BSV::Transaction::TransactionInput.new(
            prev_wtxid: BSV::Primitives::Digest.sha256d("source #{i}"),
            prev_tx_out_index: i
          )
          input.source_satoshis = 50_000 + i
          input.source_locking_script = lock_script
          input.unlocking_script_template = BSV::Transaction::P2PKH.new(priv)
          tx.add_input(input)
        end
        tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 149_000, locking_script: lock_script))
        tx.sign_all

        roundtrip = described_class.from_ef(tx.to_ef)

        expect(roundtrip.inputs.length).to eq(3)
        3.times do |i|
          expect(roundtrip.inputs[i].source_satoshis).to eq(50_000 + i)
          expect(roundtrip.inputs[i].source_locking_script.to_hex).to eq(lock_script.to_hex)
        end
        expect(roundtrip.to_ef_hex).to eq(tx.to_ef_hex)
      end
    end

    describe 'integration: build, sign, EF round-trip, verify' do
      it 'verifies input scripts after EF round-trip' do
        priv = BSV::Primitives::PrivateKey.generate
        pub = priv.public_key
        lock_script = BSV::Script::Script.p2pkh_lock(pub.hash160)

        tx = described_class.new
        input = BSV::Transaction::TransactionInput.new(
          prev_wtxid: BSV::Primitives::Digest.sha256d('source tx'),
          prev_tx_out_index: 0
        )
        input.source_satoshis = 100_000
        input.source_locking_script = lock_script
        tx.add_input(input)
        tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 99_000, locking_script: lock_script))
        tx.sign(0, priv)

        restored = described_class.from_ef(tx.to_ef)

        expect(restored.verify_input(0)).to be true
      end
    end

    describe 'standard format is unchanged' do
      it 'to_binary does not include EF marker' do
        priv = BSV::Primitives::PrivateKey.generate
        lock_script = BSV::Script::Script.p2pkh_lock(priv.public_key.hash160)

        tx = described_class.new
        input = BSV::Transaction::TransactionInput.new(
          prev_wtxid: "\x01".b * 32,
          prev_tx_out_index: 0
        )
        input.source_satoshis = 50_000
        input.source_locking_script = lock_script
        tx.add_input(input)
        tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 49_000, locking_script: lock_script))
        tx.sign(0, priv)

        standard = tx.to_binary
        expect(standard.byteslice(4, 6)).not_to eq("\x00\x00\x00\x00\x00\xEF".b)

        parsed = described_class.from_binary(standard)
        expect(parsed.txid_hex).to eq(tx.txid_hex)
      end
    end
  end
end
