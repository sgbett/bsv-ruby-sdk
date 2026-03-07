# frozen_string_literal: true

require 'spec_helper'

# Protocol conformance: SPV verification (Transaction#verify)
#
# Cross-validates the Ruby SDK's SPV verification against the patterns
# used by all three reference SDKs.
#
# Reference implementations:
#   TS SDK:  src/transaction/Transaction.ts (verify method, lines 832-954)
#   Go SDK:  spv/verify.go (Verify function)
#   Python:  transaction.py (verify method, lines 405-457)

RSpec.describe BSV::Transaction::Transaction do # rubocop:disable RSpec/MultipleDescribes
  describe 'SPV verify conformance' do
    let(:priv) { BSV::Primitives::PrivateKey.generate }
    let(:pub) { priv.public_key }
    let(:lock_script) { BSV::Script::Script.p2pkh_lock(pub.hash160) }
    let(:chain_tracker) { instance_double(BSV::Transaction::ChainTracker) }

    def build_source_tx(satoshis: 100_000)
      tx = described_class.new
      input = BSV::Transaction::TransactionInput.new(
        prev_tx_id: BSV::Primitives::Digest.sha256d('conformance'),
        prev_tx_out_index: 0
      )
      input.unlocking_script = BSV::Script::Script.from_asm('OP_TRUE')
      input.source_locking_script = BSV::Script::Script.from_asm('OP_TRUE')
      input.source_satoshis = satoshis + 1000
      tx.add_input(input)
      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: satoshis,
                      locking_script: lock_script
                    ))
      tx
    end

    def build_spending_tx(source_tx, output_sats: 90_000)
      tx = described_class.new
      input = BSV::Transaction::TransactionInput.new(
        prev_tx_id: source_tx.txid,
        prev_tx_out_index: 0
      )
      input.source_satoshis = source_tx.outputs[0].satoshis
      input.source_locking_script = source_tx.outputs[0].locking_script
      input.source_transaction = source_tx
      input.unlocking_script_template = BSV::Transaction::P2PKH.new(priv)
      tx.add_input(input)
      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: output_sats,
                      locking_script: lock_script
                    ))
      tx.sign_all
      tx
    end

    def valid_merkle_path
      instance_double(BSV::Transaction::MerklePath,
                      block_height: 800_000,
                      verify: true)
    end

    # All three SDKs: merkle path short-circuits input verification
    # TS: lines 847-864 — if merklePath.verify() returns true, mark verified and skip
    # Go: lines 45-53 — if MerklePath exists and verifies, continue without checking inputs
    # Python: lines 406-409 — if merklePath verifies, return True immediately
    it 'short-circuits on valid merkle path (all SDKs)' do
      source_tx = build_source_tx
      source_tx.merkle_path = valid_merkle_path
      # Sabotage inputs — if they were checked, verification would fail
      source_tx.inputs[0].unlocking_script = nil

      tx = build_spending_tx(source_tx)

      expect(tx.verify(chain_tracker: chain_tracker)).to be true
    end

    # All three SDKs: invalid merkle path raises/returns error
    # TS: throws Error("Merkle proof is invalid")
    # Go: returns ErrInvalidMerklePath
    # Python: raises ValueError
    it 'raises on invalid merkle path (all SDKs)' do
      source_tx = build_source_tx
      source_tx.merkle_path = instance_double(
        BSV::Transaction::MerklePath,
        block_height: 800_000,
        verify: false
      )

      tx = build_spending_tx(source_tx)

      expect { tx.verify(chain_tracker: chain_tracker) }
        .to raise_error(BSV::Transaction::VerificationError, /invalid merkle proof/)
    end

    # TS/Go: fee validation only on root transaction, not ancestors
    # TS: line 874 — "if (this === txQueue[0])" check (root only)
    # Go: lines 22-34 — feeModel check before queue loop (root only)
    it 'validates fee only on root transaction (TS/Go pattern)' do
      grandparent = build_source_tx(satoshis: 200_000)
      grandparent.merkle_path = valid_merkle_path

      # Parent: high fee (150000 in, 100001 out = 49999 sat fee)
      parent = build_spending_tx(grandparent, output_sats: 100_001)
      # Child: low fee (100001 in, 100000 out = 1 sat fee)
      child = build_spending_tx(parent, output_sats: 100_000)

      fee_model = instance_double(BSV::Transaction::FeeModel)
      allow(fee_model).to receive(:compute_fee).and_return(50)

      # Child's fee (1 sat) is below model requirement (50 sat)
      expect { child.verify(chain_tracker: chain_tracker, fee_model: fee_model) }
        .to raise_error(BSV::Transaction::VerificationError, /insufficient fee/)
    end

    # TS/Python: verify outputs ≤ inputs
    # TS: lines 935-948 — sums outputs and inputs, returns false if violated
    # Python: lines 451-457 — returns output_total <= input_total
    it 'checks output ≤ input constraint (TS/Python pattern)' do
      source_tx = build_source_tx(satoshis: 100_000)
      source_tx.merkle_path = valid_merkle_path

      tx = described_class.new
      input = BSV::Transaction::TransactionInput.new(
        prev_tx_id: source_tx.txid,
        prev_tx_out_index: 0
      )
      input.source_satoshis = 100_000
      input.source_locking_script = BSV::Script::Script.from_asm('OP_TRUE')
      input.unlocking_script = BSV::Script::Script.from_asm('OP_TRUE')
      input.source_transaction = source_tx
      tx.add_input(input)
      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: 200_000,
                      locking_script: lock_script
                    ))

      expect { tx.verify(chain_tracker: chain_tracker) }
        .to raise_error(BSV::Transaction::VerificationError, /outputs.*exceed inputs/)
    end

    # All three SDKs: deduplication of verified transactions
    # TS: uses txQueue with verifiedTxids Set
    # Go: uses verifiedTxids map[string]bool
    # Python: implicit via recursive verify returning True on already-verified
    it 'deduplicates verified transactions (all SDKs)' do
      source_tx = build_source_tx(satoshis: 200_000)
      path = instance_double(BSV::Transaction::MerklePath,
                             block_height: 800_000)
      allow(path).to receive(:verify).and_return(true)
      source_tx.merkle_path = path

      tx = described_class.new
      2.times do
        input = BSV::Transaction::TransactionInput.new(
          prev_tx_id: source_tx.txid,
          prev_tx_out_index: 0
        )
        input.source_satoshis = source_tx.outputs[0].satoshis
        input.source_locking_script = source_tx.outputs[0].locking_script
        input.source_transaction = source_tx
        input.unlocking_script_template = BSV::Transaction::P2PKH.new(priv)
        tx.add_input(input)
      end
      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: 50_000,
                      locking_script: lock_script
                    ))
      tx.sign_all

      tx.verify(chain_tracker: chain_tracker)
      expect(path).to have_received(:verify).once
    end

    # All three SDKs: script execution for each input
    # TS: Spend.validate() for each input
    # Go: interpreter.Execute() for each input
    # Python: Spend.validate() for each input
    it 'executes scripts for each input (all SDKs)' do
      source_tx = build_source_tx
      source_tx.merkle_path = valid_merkle_path

      tx = build_spending_tx(source_tx)
      # Valid P2PKH scripts — should pass
      expect(tx.verify(chain_tracker: chain_tracker)).to be true
    end

    # All three SDKs: recursive/queue-based ancestry verification
    # TS: queue-based (lines 886-933)
    # Go: queue-based (lines 36-79)
    # Python: recursive (line 429)
    it 'recursively verifies ancestry chain (all SDKs)' do
      grandparent = build_source_tx(satoshis: 200_000)
      grandparent.merkle_path = valid_merkle_path

      parent = build_spending_tx(grandparent, output_sats: 150_000)
      child = build_spending_tx(parent, output_sats: 100_000)

      expect(child.verify(chain_tracker: chain_tracker)).to be true
    end
  end
end

RSpec.describe BSV::Transaction::FeeModel do
  describe 'integration with verify' do
    let(:priv) { BSV::Primitives::PrivateKey.generate }
    let(:lock_script) { BSV::Script::Script.p2pkh_lock(priv.public_key.hash160) }
    let(:chain_tracker) { instance_double(BSV::Transaction::ChainTracker) }

    it 'SatoshisPerKilobyte integrates with verify' do
      source_tx = BSV::Transaction::Transaction.new
      input = BSV::Transaction::TransactionInput.new(
        prev_tx_id: BSV::Primitives::Digest.sha256d('fee-test'),
        prev_tx_out_index: 0
      )
      input.unlocking_script = BSV::Script::Script.from_asm('OP_TRUE')
      input.source_locking_script = BSV::Script::Script.from_asm('OP_TRUE')
      input.source_satoshis = 200_000
      source_tx.add_input(input)
      source_tx.add_output(BSV::Transaction::TransactionOutput.new(
                             satoshis: 100_000,
                             locking_script: lock_script
                           ))
      source_tx.merkle_path = instance_double(BSV::Transaction::MerklePath,
                                              block_height: 800_000,
                                              verify: true)

      tx = BSV::Transaction::Transaction.new
      spend_input = BSV::Transaction::TransactionInput.new(
        prev_tx_id: source_tx.txid,
        prev_tx_out_index: 0
      )
      spend_input.source_satoshis = 100_000
      spend_input.source_locking_script = lock_script
      spend_input.source_transaction = source_tx
      spend_input.unlocking_script_template = BSV::Transaction::P2PKH.new(priv)
      tx.add_input(spend_input)
      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: 50_000,
                      locking_script: lock_script
                    ))
      tx.sign_all

      # Fee is 50000 sat — well above any reasonable model
      model = BSV::Transaction::FeeModels::SatoshisPerKilobyte.new(value: 50)
      expect(tx.verify(chain_tracker: chain_tracker, fee_model: model)).to be true
    end
  end
end
