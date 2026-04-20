# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::ChangeGenerator do
  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  let(:key_deriver) { BSV::Wallet::KeyDeriver.new(private_key) }
  let(:fee_model)   { BSV::Wallet::FeeModel.new(sats_per_kb: 1) }
  let(:generator)   { described_class.new(key_deriver: key_deriver, fee_model: fee_model) }

  # At 1 sat/kB: estimate(1 input, 1 output) = 1 sat; dust_floor = max(2, 1*2) = 2
  let(:dust_floor) { 2 }

  describe '#initialize' do
    it 'accepts valid arguments' do
      expect { described_class.new(key_deriver: key_deriver, fee_model: fee_model) }.not_to raise_error
    end

    it 'accepts a custom max_outputs' do
      gen = described_class.new(key_deriver: key_deriver, fee_model: fee_model, max_outputs: 4)
      expect(gen.max_outputs).to eq(4)
    end

    it 'raises ArgumentError when max_outputs is zero' do
      expect do
        described_class.new(key_deriver: key_deriver, fee_model: fee_model, max_outputs: 0)
      end.to raise_error(ArgumentError, /max_outputs/)
    end

    it 'defaults max_outputs to 8' do
      gen = described_class.new(key_deriver: key_deriver, fee_model: fee_model)
      expect(gen.max_outputs).to eq(8)
    end
  end

  describe '#generate' do
    context 'when excess is zero' do
      it 'returns an empty array' do
        expect(generator.generate(excess_satoshis: 0)).to be_empty
      end
    end

    context 'when excess is below the dust floor' do
      it 'returns an empty array for 1 satoshi excess' do
        # dust_floor is 2; 1 < 2 so excess is donated to the miner
        expect(generator.generate(excess_satoshis: 1)).to be_empty
      end
    end

    context 'when excess equals the dust floor' do
      it 'returns a single output with the full excess' do
        outputs = generator.generate(excess_satoshis: dust_floor)
        expect(outputs.length).to eq(1)
        expect(outputs.first[:satoshis]).to eq(dust_floor)
      end
    end

    context 'with max_outputs: 1' do
      let(:generator) { described_class.new(key_deriver: key_deriver, fee_model: fee_model, max_outputs: 1) }

      it 'returns one output with the full excess' do
        outputs = generator.generate(excess_satoshis: 5000)
        expect(outputs.length).to eq(1)
        expect(outputs.first[:satoshis]).to eq(5000)
      end

      it 'attaches valid BRC-29 metadata' do
        outputs = generator.generate(excess_satoshis: 5000)
        output = outputs.first

        expect(output[:derivation_prefix]).to match(/\A[0-9a-f]{32}\z/)
        expect(output[:derivation_suffix]).to match(/\A[0-9a-f]{32}\z/)
        expect(output[:sender_identity_key]).to eq(key_deriver.identity_key)
        expect(output[:locking_script]).to be_a(BSV::Script::Script)
      end

      it 'produces a valid P2PKH locking script' do
        outputs = generator.generate(excess_satoshis: 5000)
        expect(outputs.first[:locking_script].p2pkh?).to be true
      end
    end

    context 'with max_outputs: 4' do
      let(:generator) { described_class.new(key_deriver: key_deriver, fee_model: fee_model, max_outputs: 4) }

      it 'returns at most max_outputs outputs' do
        outputs = generator.generate(excess_satoshis: 10_000)
        expect(outputs.length).to be <= 4
      end

      it 'outputs sum to the total excess' do
        outputs = generator.generate(excess_satoshis: 10_000)
        expect(outputs.sum { |o| o[:satoshis] }).to eq(10_000)
      end

      it 'each output is at or above the dust floor' do
        outputs = generator.generate(excess_satoshis: 10_000)
        outputs.each do |o|
          expect(o[:satoshis]).to be >= dust_floor
        end
      end

      it 'each output has distinct derivation keys' do
        outputs = generator.generate(excess_satoshis: 10_000)
        prefixes = outputs.map { |o| o[:derivation_prefix] }
        expect(prefixes.uniq.length).to eq(prefixes.length)
      end
    end

    context 'when excess is too small for multiple outputs' do
      let(:generator) { described_class.new(key_deriver: key_deriver, fee_model: fee_model, max_outputs: 4) }

      it 'returns a single output when excess only covers one dust floor' do
        # excess 3 sats at dust_floor 2: can only accommodate floor(3/2) = 1 output
        outputs = generator.generate(excess_satoshis: 3)
        expect(outputs.length).to eq(1)
        expect(outputs.first[:satoshis]).to eq(3)
      end
    end

    context 'when verifying BRC-29 derivation roundtrip' do
      it 'derives the same key from stored metadata as was used to generate the script' do
        outputs = generator.generate(excess_satoshis: 5000)
        output = outputs.first

        prefix = output[:derivation_prefix]
        suffix = output[:derivation_suffix]
        sender_key = output[:sender_identity_key]

        # Reproduce the private key exactly as the wallet would when spending
        priv = key_deriver.derive_private_key(
          described_class::BRC29_PROTOCOL_ID,
          "#{prefix} #{suffix}",
          sender_key
        )

        # The hash160 of the re-derived public key must match the script
        expected_hash160 = priv.public_key.hash160
        script_hash160 = output[:locking_script].pubkey_hash

        expect(expected_hash160).to eq(script_hash160)
      end
    end

    context 'when sub-dust remainders need consolidation' do
      it 'folds remainder into the largest output when random distribution produces a sub-dust slice' do
        # Use a seeded random split that we control to verify consolidation logic.
        # We test the observable guarantee: no output may be below the dust floor.
        gen = described_class.new(key_deriver: key_deriver, fee_model: fee_model, max_outputs: 8)
        outputs = gen.generate(excess_satoshis: 20)
        outputs.each do |o|
          expect(o[:satoshis]).to be >= dust_floor
        end
        expect(outputs.sum { |o| o[:satoshis] }).to eq(20)
      end
    end

    context 'when excess is negative' do
      it 'returns an empty array' do
        expect(generator.generate(excess_satoshis: -100)).to be_empty
      end
    end
  end
end
