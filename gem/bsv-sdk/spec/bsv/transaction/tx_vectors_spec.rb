# frozen_string_literal: true

require 'spec_helper'

# Cross-validation of transaction serialisation against TS SDK test vectors.
# Source: bsv-blockchain/ts-stack packages/sdk/src/transaction/__tests/tx.valid.vectors.ts
#
# Each vector: [[[prevout_hash, prevout_index, scriptPubKey], ...], serialised_tx_hex, flags]
# We test round-trip: from_hex(hex).to_hex == hex

RSpec.describe 'Transaction serialisation vectors (TS SDK)' do
  let(:vectors) do
    JSON.parse(File.read(File.expand_path('../../fixtures/tx_vectors.json', __dir__)))
  end

  it 'loads the fixture file' do
    expect(vectors).to be_an(Array)
    expect(vectors.length).to be > 0
  end

  describe 'round-trip serialisation' do
    it 'deserialises and re-serialises all valid transaction vectors' do
      pass_count = 0
      fail_count = 0
      failures = []

      vectors.each_with_index do |vec, idx|
        # Vector format: [prevouts_array, tx_hex, flags]
        # The tx_hex is at index 1 (after the prevouts array)
        tx_hex = vec[1]
        next unless tx_hex.is_a?(String) && tx_hex.length > 10

        begin
          tx = BSV::Transaction::Tx.from_hex(tx_hex)
          round_tripped = tx.to_hex

          if round_tripped == tx_hex
            pass_count += 1
          else
            fail_count += 1
            if failures.length < 10
              failures << "Vector #{idx}: round-trip mismatch " \
                          "(input #{tx_hex.length} chars, output #{round_tripped.length} chars)"
            end
          end
        rescue StandardError => e
          fail_count += 1
          failures << "Vector #{idx}: #{e.class} - #{e.message}" if failures.length < 10
        end
      end

      aggregate_failures "tx round-trip results (#{pass_count} passed, #{fail_count} failed)" do
        expect(fail_count).to eq(0), "#{fail_count} vectors failed:\n#{failures.join("\n")}"
      end
    end
  end

  describe 'txid computation' do
    it 'produces consistent txids for all vectors' do
      pass_count = 0
      fail_count = 0

      vectors.each do |vec|
        tx_hex = vec[1]
        next unless tx_hex.is_a?(String) && tx_hex.length > 10

        begin
          tx = BSV::Transaction::Tx.from_hex(tx_hex)
          txid = tx.txid_hex

          # txid should be 64 hex chars (32 bytes)
          if txid.length == 64
            pass_count += 1
          else
            fail_count += 1
          end
        rescue StandardError
          fail_count += 1
        end
      end

      expect(fail_count).to eq(0), "#{fail_count} txid computations failed (#{pass_count} passed)"
    end
  end
end
