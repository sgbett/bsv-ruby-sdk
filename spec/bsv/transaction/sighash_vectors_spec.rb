# frozen_string_literal: true

# Cross-validation of BIP-143 sighash computation against TS SDK test vectors.
# Source: bsv-blockchain/ts-sdk src/primitives/__tests/sighash.vectors.ts
#
# Each vector: [raw_tx_hex, script_hex, input_index, hash_type, expected_sighash_hex]
# All vectors use SIGHASH_FORKID (BIP-143).

RSpec.describe 'Sighash vectors (TS SDK)' do # rubocop:disable RSpec/DescribeClass
  let(:vectors) do
    JSON.parse(File.read(File.expand_path('../../fixtures/sighash_vectors.json', __dir__)))
  end

  it 'loads the fixture file' do
    expect(vectors).to be_an(Array)
    expect(vectors.length).to be > 0
    expect(vectors.first.length).to eq(5)
  end

  it 'computes correct sighash for all TS SDK vectors' do
    pass_count = 0
    fail_count = 0
    failures = []

    vectors.each_with_index do |vec, idx|
      raw_tx_hex, script_hex, input_index, hash_type, expected_hex = vec

      begin
        tx = BSV::Transaction::Transaction.from_hex(raw_tx_hex)
        subscript = BSV::Script::Script.from_hex(script_hex)

        # TS SDK vectors assume source_satoshis = 0 for sighash computation
        input = tx.inputs[input_index]
        input.source_satoshis = 0
        input.source_locking_script = subscript

        # Handle negative hash types (two's complement 32-bit)
        sighash_type = hash_type & 0xFFFFFFFF

        result = tx.sighash(input_index, sighash_type, subscript: subscript)
        # TS SDK vectors store expected hash in display order (byte-reversed)
        actual_hex = result.reverse.unpack1('H*')

        if actual_hex == expected_hex
          pass_count += 1
        else
          fail_count += 1
          failures << "Vector #{idx}: expected #{expected_hex}, got #{actual_hex}" if failures.length < 10
        end
      rescue StandardError => e
        fail_count += 1
        failures << "Vector #{idx}: #{e.class} - #{e.message}" if failures.length < 10
      end
    end

    aggregate_failures "sighash vector results (#{pass_count} passed, #{fail_count} failed of #{vectors.length})" do
      expect(fail_count).to eq(0), "#{fail_count} vectors failed:\n#{failures.join("\n")}"
    end
  end
end
