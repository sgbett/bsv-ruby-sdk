# frozen_string_literal: true

require 'spec_helper'
require 'base64'

# Protocol conformance: BEEF-based SPV verification (Tx#verify)
#
# Parses real BEEF bundles from the reference SDK test vectors and runs
# Tx#verify against them. This validates end-to-end cross-SDK
# conformance for SPV verification using actual BEEF-encoded data rather
# than hand-built mocked transactions.
#
# Reference implementations:
#   Go SDK:  TestSPVVerify, TestSPVVerifyScripts, TestSPVVerifyWithSufficientFee,
#            TestSPVVerifyWithInsufficientFee (transaction/spv_test.go)
#   TS SDK:  "Verifies the transaction from the BEEF spec",
#            "Verifies tx scripts only when our input has no MerklePath"
#
# Vectors:
#   BRC62 (V1 BEEF): canonical corpus sdk/transactions/serialization.json tx-003
#   BEEFSet (V2 BEEF), BEEF (V1 base64), Issue96BeefHex: Ruby-local inline fixtures (see beef_spec.rb)

# A chain tracker that always accepts any merkle root as valid.
# Used for BEEF conformance tests where we trust the embedded proofs
# and simply want to exercise the verification logic itself.
class AlwaysTrueChainTracker < BSV::Transaction::ChainTracker
  def valid_root_for_height?(_root, _height)
    true
  end

  def current_height
    900_000
  end
end

RSpec.describe 'BEEF-based SPV verification conformance' do
  let(:always_true_tracker) { AlwaysTrueChainTracker.new }

  let(:brc62_hex) do
    vector = nil
    ConformanceVectors.each_canonical_vector('sdk.transactions.serialization') do |_env, v|
      vector = v if v['id'] == 'tx-003'
    end
    vector.dig('input', 'beef_hex')
  end
  let(:beef_base64) { BEEF_V1_B64 }
  let(:beef_set_hex) { BEEF_V2_SET_HEX }
  let(:issue96_hex) { BEEF_ISSUE96_HEX }

  # --- Happy-path verification with always-true chain tracker ---

  describe 'BRC62Hex (V1 BEEF)' do
    subject(:tx) { BSV::Transaction::Tx.from_beef_hex(brc62_hex) }

    it 'parses successfully and verifies with always-true chain tracker' do
      expect(tx.verify(chain_tracker: always_true_tracker)).to be true
    end
  end

  describe 'BEEF base64 (V1 multi-transaction BEEF)' do
    subject(:tx) do
      data = Base64.strict_decode64(beef_base64)
      BSV::Transaction::Tx.from_beef(data)
    end

    it 'parses successfully and verifies with always-true chain tracker' do
      expect(tx.verify(chain_tracker: always_true_tracker)).to be true
    end
  end

  describe 'BEEFSet (V2 BEEF)' do
    subject(:tx) { BSV::Transaction::Tx.from_beef_hex(beef_set_hex) }

    it 'parses successfully and verifies with always-true chain tracker' do
      expect(tx.verify(chain_tracker: always_true_tracker)).to be true
    end
  end

  describe 'Issue96BeefHex (V1 BEEF — regression for "no leaves at height: 1")' do
    subject(:tx) { BSV::Transaction::Tx.from_beef_hex(issue96_hex) }

    it 'parses successfully and verifies with always-true chain tracker' do
      expect(tx.verify(chain_tracker: always_true_tracker)).to be true
    end
  end

  # --- Fee model integration (Go SDK: TestSPVVerifyWithSufficientFee / TestSPVVerifyWithInsufficientFee) ---

  describe 'fee model integration using BRC62Hex' do
    subject(:tx) { BSV::Transaction::Tx.from_beef_hex(brc62_hex) }

    it 'verifies when fee model rate is low (passes)' do
      # 1 sat/kB is effectively zero — any real transaction fee will exceed this
      fee_model = BSV::Transaction::FeeModels::SatoshisPerKilobyte.new(value: 1)
      expect(tx.verify(chain_tracker: always_true_tracker, fee_model: fee_model)).to be true
    end

    it 'raises VerificationError(:insufficient_fee) when fee model rate is extremely high' do
      # 1_000_000 sat/kB means roughly 1 sat/byte minimum — most test vectors
      # carry very small fees, so this should trigger an insufficient fee error
      fee_model = BSV::Transaction::FeeModels::SatoshisPerKilobyte.new(value: 1_000_000)
      expect { tx.verify(chain_tracker: always_true_tracker, fee_model: fee_model) }
        .to raise_error(BSV::Transaction::VerificationError) { |e|
          expect(e.code).to eq(:insufficient_fee)
        }
    end
  end

  # --- Corrupt merkle proof ---

  describe 'corrupt merkle proof' do
    it 'raises VerificationError(:invalid_merkle_proof) when a BUMP hash is flipped' do
      tx = BSV::Transaction::Tx.from_beef_hex(brc62_hex)

      # Find a mined ancestor (one that has a merkle_path attached)
      mined_tx = nil
      queue = [tx]
      visited = {}
      until queue.empty?
        candidate = queue.shift
        next if visited[candidate.txid_hex]

        visited[candidate.txid_hex] = true
        if candidate.merkle_path
          mined_tx = candidate
          break
        end
        candidate.inputs.each do |input|
          queue << input.source_transaction if input.source_transaction
        end
      end

      expect(mined_tx).not_to be_nil, 'expected BEEF to contain at least one mined ancestor'

      # Record the correct merkle root so we can build a tracker that rejects
      # any other root. This means when we corrupt a sibling hash the recomputed
      # root will differ and the tracker will return false.
      original_path = mined_tx.merkle_path
      correct_root = original_path.compute_root_hex(mined_tx.txid_hex)
      correct_height = original_path.block_height

      root_checking_tracker = Class.new(BSV::Transaction::ChainTracker) do
        define_method(:valid_root_for_height?) do |root, height|
          # Only accept the originally computed root at the recorded height
          root == correct_root && height == correct_height
        end

        def current_height
          900_000
        end
      end.new

      # Verify the uncorrupted BEEF succeeds with this tracker
      expect(tx.verify(chain_tracker: root_checking_tracker)).to be true

      # Now corrupt the merkle path: flip every byte in a non-txid sibling hash
      # at level 0 so the recomputed root will not match.
      original_levels = original_path.path

      corrupted_levels = original_levels.map.with_index do |level, level_idx|
        if level_idx.zero?
          level.map do |elem|
            next elem if elem.txid || elem.duplicate || elem.hash.nil?

            corrupted_hash = elem.hash.bytes.map { |b| b ^ 0xFF }.pack('C*')
            BSV::Transaction::MerklePath::PathElement.new(
              offset: elem.offset,
              hash: corrupted_hash,
              txid: false,
              duplicate: false
            )
          end
        else
          level
        end
      end

      corrupted_path = BSV::Transaction::MerklePath.new(
        block_height: original_path.block_height,
        path: corrupted_levels
      )

      # Re-parse a fresh copy so the source_locking_script population is clean
      tx2 = BSV::Transaction::Tx.from_beef_hex(brc62_hex)
      mined_tx2 = nil
      queue2 = [tx2]
      visited2 = {}
      until queue2.empty?
        candidate = queue2.shift
        next if visited2[candidate.txid_hex]

        visited2[candidate.txid_hex] = true
        if candidate.merkle_path
          mined_tx2 = candidate
          break
        end
        candidate.inputs.each do |input|
          queue2 << input.source_transaction if input.source_transaction
        end
      end

      mined_tx2.merkle_path = corrupted_path

      expect { tx2.verify(chain_tracker: root_checking_tracker) }
        .to raise_error(BSV::Transaction::VerificationError) { |e|
          expect(e.code).to eq(:invalid_merkle_proof)
        }
    end
  end

  # --- Tampered transaction ---

  describe 'tampered subject transaction' do
    it 'fails verification when an output amount is modified' do
      tx = BSV::Transaction::Tx.from_beef_hex(brc62_hex)

      # Corrupt the subject transaction's first output satoshi value.
      # This will cause the output ≤ input check or script verification to fail,
      # since the ancestry chain's source_satoshis no longer match what the
      # scripts expect.
      original_satoshis = tx.outputs[0].satoshis
      tx.outputs[0].satoshis = original_satoshis + 1_000_000

      # After tampering, the output total exceeds the input total: outputs > inputs
      expect { tx.verify(chain_tracker: always_true_tracker) }
        .to raise_error(BSV::Transaction::VerificationError)
    end
  end
end
