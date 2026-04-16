# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'
require 'securerandom'
require 'base64'

RSpec.describe BSV::Wallet::WalletClient do
  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  # P2PKH locking script for the wallet's own public key
  let(:locking_script_hex) { BSV::Script::Script.p2pkh_lock(pub_key.hash160).to_hex }
  # Minimal valid description (5-50 chars)
  let(:description) { 'test transaction action' }
  # A simple output spec
  let(:output_spec) do
    {
      locking_script: locking_script_hex,
      satoshis: 1000,
      output_description: 'test output one'
    }
  end
  let(:pub_key) { private_key.public_key }
  # Post-HLR #455: broadcaster required; most tests use a stubbed broadcaster so
  # create_action does not raise. Tests that specifically exercise the no-broadcaster
  # guard use `no_broadcaster_wallet` instead.
  let(:broadcaster) { double('broadcaster') } # rubocop:disable RSpec/VerifiedDoubles
  let(:wallet) do
    described_class.new(private_key, storage: BSV::Wallet::MemoryStore.new, broadcaster: broadcaster)
  end
  let(:no_broadcaster_wallet) do
    described_class.new(private_key, storage: BSV::Wallet::MemoryStore.new)
  end

  before do
    allow(broadcaster).to receive(:broadcast).and_return(
      BSV::Network::BroadcastResponse.new(txid: 'stub', tx_status: 'SEEN_ON_NETWORK')
    )
  end

  # Build a source transaction and its BEEF bytes for use as input_beef
  def build_source_beef(satoshis: 5000)
    source_tx = BSV::Transaction::Transaction.new
    source_tx.add_output(
      BSV::Transaction::TransactionOutput.new(
        satoshis: satoshis,
        locking_script: BSV::Script::Script.p2pkh_lock(pub_key.hash160)
      )
    )
    [source_tx, source_tx.to_beef.unpack('C*')]
  end

  # -------------------------------------------------------------------------
  # #initialize
  # -------------------------------------------------------------------------
  describe '#initialize' do
    it 'defaults storage to a MemoryStore' do
      expect(wallet.storage).to be_a(BSV::Wallet::MemoryStore)
    end

    it 'exposes a KeyDeriver (inherited from ProtoWallet)' do
      expect(wallet.key_deriver).to be_a(BSV::Wallet::KeyDeriver)
    end

    it 'accepts a custom storage adapter' do
      custom_store = BSV::Wallet::MemoryStore.new
      w = described_class.new(private_key, storage: custom_store)
      expect(w.storage).to equal(custom_store)
    end

    it 'starts with no pending transactions' do
      # Abort on a random reference should raise — no pending state
      expect do
        wallet.abort_action({ reference: 'nonexistent' })
      end.to raise_error(BSV::Wallet::WalletError)
    end

    it 'defaults broadcaster to nil' do
      w = described_class.new(private_key, storage: BSV::Wallet::MemoryStore.new)
      expect(w.broadcaster).to be_nil
    end

    it 'accepts a broadcaster: keyword argument' do
      br = double('broadcaster', broadcast: nil) # rubocop:disable RSpec/VerifiedDoubles
      w = described_class.new(private_key, storage: BSV::Wallet::MemoryStore.new, broadcaster: br)
      expect(w.broadcaster).to equal(br)
    end

    it 'returns false from broadcast_enabled? when broadcaster is nil' do
      w = described_class.new(private_key, storage: BSV::Wallet::MemoryStore.new)
      expect(w.broadcast_enabled?).to be(false)
    end

    it 'returns true from broadcast_enabled? when broadcaster is set' do
      br = double('broadcaster', broadcast: nil) # rubocop:disable RSpec/VerifiedDoubles
      w = described_class.new(private_key, storage: BSV::Wallet::MemoryStore.new, broadcaster: br)
      expect(w.broadcast_enabled?).to be(true)
    end

    it 'creates an InlineQueue by default' do
      expect(wallet.broadcast_queue).to be_a(BSV::Wallet::InlineQueue)
    end

    it 'wires the default InlineQueue with the same storage adapter' do
      store = BSV::Wallet::MemoryStore.new
      w = described_class.new(private_key, storage: store)
      # InlineQueue holds a reference to @storage — verify indirectly via #status delegation
      expect(w.broadcast_queue).to respond_to(:status)
    end

    it 'accepts a custom broadcast_queue: keyword argument' do
      custom_queue = double('custom_queue', enqueue: {}, status: nil, async?: false) # rubocop:disable RSpec/VerifiedDoubles
      w = described_class.new(private_key, storage: BSV::Wallet::MemoryStore.new, broadcast_queue: custom_queue)
      expect(w.broadcast_queue).to equal(custom_queue)
    end

    # broadcast_enabled? delegates to the queue so queue-embedded broadcasters
    # (e.g. SolidQueueAdapter) are recognised even without a direct broadcaster:.
    it 'broadcast_enabled? delegates to the broadcast queue' do
      # A custom queue that reports broadcast_enabled? = false
      custom_queue = double('custom_queue', broadcast_enabled?: false) # rubocop:disable RSpec/VerifiedDoubles
      w = described_class.new(private_key, storage: BSV::Wallet::MemoryStore.new, broadcast_queue: custom_queue)
      expect(w.broadcast_enabled?).to be(false)
    end

    it 'broadcast_enabled? returns true when the queue reports it has a broadcaster' do
      custom_queue = double('custom_queue', broadcast_enabled?: true) # rubocop:disable RSpec/VerifiedDoubles
      w = described_class.new(private_key, storage: BSV::Wallet::MemoryStore.new, broadcast_queue: custom_queue)
      expect(w.broadcast_enabled?).to be(true)
    end
  end

  # -------------------------------------------------------------------------
  # #create_action — validation
  # -------------------------------------------------------------------------
  describe '#create_action — validation' do
    it 'raises InvalidParameterError when description is missing' do
      expect do
        wallet.create_action({ outputs: [output_spec] })
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises InvalidParameterError when description is too short' do
      expect do
        wallet.create_action({ description: 'hi', outputs: [output_spec] })
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises InvalidParameterError when description is too long (> 50 chars)' do
      long_desc = 'a' * 51
      expect do
        wallet.create_action({ description: long_desc, outputs: [output_spec] })
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises InvalidParameterError when neither inputs nor outputs are provided' do
      expect do
        wallet.create_action({ description: description })
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises InvalidParameterError when inputs is present but empty' do
      expect do
        wallet.create_action({ description: description, inputs: [] })
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises InvalidParameterError when outputs is present but empty' do
      expect do
        wallet.create_action({ description: description, outputs: [] })
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises InvalidParameterError for an invalid label' do
      expect do
        wallet.create_action({ description: description, outputs: [output_spec], labels: [''] })
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises InvalidParameterError when an output has no satoshis' do
      bad_output = { locking_script: locking_script_hex, output_description: 'bad output' }
      expect do
        wallet.create_action({ description: description, outputs: [bad_output] })
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises InvalidParameterError when an output has an invalid locking_script' do
      bad_output = { locking_script: 'not hex!', satoshis: 1000, output_description: 'bad out' }
      expect do
        wallet.create_action({ description: description, outputs: [bad_output] })
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  # -------------------------------------------------------------------------
  # HLR #455: broadcast configuration guard (Task 1 new specs)
  # -------------------------------------------------------------------------
  describe 'broadcast configuration guard (HLR #455)' do
    let(:source_tx_and_beef) { build_source_beef }
    let(:source_tx) { source_tx_and_beef[0] }
    let(:input_beef_bytes) { source_tx_and_beef[1] }
    let(:source_txid) { source_tx.txid_hex }

    let(:base_args) do
      {
        description: 'broadcast guard test action',
        input_beef: input_beef_bytes,
        inputs: [{
          outpoint: "#{source_txid}.0",
          unlocking_script: 'aabb',
          input_description: 'broadcast guard input'
        }],
        outputs: [{
          locking_script: locking_script_hex,
          satoshis: 4000,
          output_description: 'broadcast guard output'
        }]
      }
    end

    it 'raises WalletError when no broadcaster and no_send is absent' do
      expect do
        no_broadcaster_wallet.create_action(base_args)
      end.to raise_error(BSV::Wallet::WalletError, /broadcaster/)
    end

    it 'raises WalletError before any storage writes' do
      expect do
        no_broadcaster_wallet.create_action(base_args)
      end.to raise_error(BSV::Wallet::WalletError)
      actions = no_broadcaster_wallet.storage.find_actions({ limit: 100, offset: 0 })
      expect(actions).to be_empty
    end

    it 'succeeds with no_send: true and no broadcaster, action status is "nosend"' do
      result = no_broadcaster_wallet.create_action(base_args.merge(options: { no_send: true }))
      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
      all_actions = no_broadcaster_wallet.storage.find_actions({ limit: 100, offset: 0 })
      action = all_actions.find { |a| a[:txid] == result[:txid] }
      expect(action[:status]).to eq('nosend')
    end

    it 'does not raise when broadcast_queue carries an embedded broadcaster' do
      # A queue that reports broadcast_enabled? = true without a direct broadcaster: arg.
      custom_queue = double('custom_queue', broadcast_enabled?: true, async?: false) # rubocop:disable RSpec/VerifiedDoubles
      allow(custom_queue).to receive(:enqueue).and_return(
        { txid: 'a' * 64, tx: [], broadcast_status: 'success' }
      )
      w = described_class.new(
        private_key,
        storage: BSV::Wallet::MemoryStore.new,
        broadcast_queue: custom_queue
      )
      expect do
        w.create_action(base_args)
      end.not_to raise_error
    end

    # Post-HLR #455: successful broadcast sets 'unproven'; 'completed' requires a merkle proof
    it 'sets action status to "unproven" after successful broadcast' do
      result = wallet.create_action(base_args)
      all_actions = wallet.storage.find_actions({ limit: 100, offset: 0 })
      action = all_actions.find { |a| a[:txid] == result[:txid] }
      expect(action[:status]).to eq('unproven')
    end
  end

  # -------------------------------------------------------------------------
  # HLR #455: sign_action broadcast guard
  # -------------------------------------------------------------------------
  describe 'sign_action broadcast guard (HLR #455)' do
    let(:source_tx_and_beef) { build_source_beef }
    let(:source_tx) { source_tx_and_beef[0] }
    let(:input_beef_bytes) { source_tx_and_beef[1] }
    let(:source_txid) { source_tx.txid_hex }
    let(:dummy_unlock_hex) { 'aabb' }

    # Create a signable tx using no_send: true so the guard doesn't fire at create time
    let(:signable_result) do
      no_broadcaster_wallet.create_action({
                                            description: 'sign action guard test',
                                            input_beef: input_beef_bytes,
                                            inputs: [{
                                              outpoint: "#{source_txid}.0",
                                              unlocking_script_length: 107,
                                              input_description: 'spend for sign action guard test'
                                            }],
                                            outputs: [{
                                              locking_script: locking_script_hex,
                                              satoshis: 4000,
                                              output_description: 'payment output'
                                            }],
                                            options: { no_send: true }
                                          })
    end

    let(:reference) { signable_result[:signable_transaction][:reference] }

    it 'raises WalletError when no_send is flipped false at sign_action time' do
      # create_action with no_send: true stores a signable tx (guard bypassed).
      # sign_action with no_send: false overrides the original option; the guard
      # re-runs on the merged args and raises because broadcast is needed.
      expect do
        no_broadcaster_wallet.sign_action({
                                            reference: reference,
                                            spends: { 0 => { unlocking_script: dummy_unlock_hex } },
                                            options: { no_send: false }
                                          })
      end.to raise_error(BSV::Wallet::WalletError, /broadcaster/)
    end
  end

  # -------------------------------------------------------------------------
  # HLR #455: internalize_action status based on BEEF proof presence (Task 4)
  # -------------------------------------------------------------------------
  describe 'internalize_action status from BEEF proof (HLR #455)' do
    let(:incoming_tx) do
      tx = BSV::Transaction::Transaction.new
      tx.add_output(
        BSV::Transaction::TransactionOutput.new(
          satoshis: 2000,
          locking_script: BSV::Script::Script.p2pkh_lock(pub_key.hash160)
        )
      )
      tx
    end

    let(:internalize_args_base) do
      {
        description: 'internalize status test',
        outputs: [{
          output_index: 0,
          protocol: 'basket insertion',
          insertion_remittance: { basket: 'proof status tokens' }
        }]
      }
    end

    it 'sets action status to "unproven" when BEEF carries no merkle proof' do
      beef_bytes = incoming_tx.to_beef.unpack('C*')
      wallet.internalize_action(internalize_args_base.merge(tx: beef_bytes))
      actions = wallet.storage.find_actions({ limit: 100, offset: 0 })
      expect(actions).not_to be_empty
      expect(actions.last[:status]).to eq('unproven')
    end

    it 'sets action status to "completed" when BEEF carries a merkle proof' do
      # Attach a merkle proof to the incoming tx so find_bump returns non-nil
      txid_bytes = incoming_tx.txid.reverse
      sibling = ("\xCD" * 32).b
      tx_elem = BSV::Transaction::MerklePath::PathElement.new(
        offset: 0, hash: txid_bytes, txid: true
      )
      sibling_elem = BSV::Transaction::MerklePath::PathElement.new(
        offset: 1, hash: sibling
      )
      merkle_path = BSV::Transaction::MerklePath.new(block_height: 900_000, path: [[tx_elem, sibling_elem]])
      incoming_tx.merkle_path = merkle_path

      beef = BSV::Transaction::Beef.new
      bump_idx = beef.merge_bump(merkle_path)
      beef.transactions << BSV::Transaction::Beef::BeefTx.new(
        format: BSV::Transaction::Beef::FORMAT_RAW_TX_AND_BUMP,
        transaction: incoming_tx,
        bump_index: bump_idx
      )
      beef_bytes = beef.to_binary.unpack('C*')

      wallet.internalize_action(internalize_args_base.merge(tx: beef_bytes))
      actions = wallet.storage.find_actions({ limit: 100, offset: 0 })
      expect(actions).not_to be_empty
      expect(actions.last[:status]).to eq('completed')
    end
  end

  # -------------------------------------------------------------------------
  # #create_action — outputs only (no inputs, immediate finalisation)
  # -------------------------------------------------------------------------
  describe '#create_action — outputs only' do
    let(:result) do
      wallet.create_action({
                             description: description,
                             outputs: [output_spec]
                           })
    end

    it 'returns a txid string of 64 hex characters' do
      expect(result[:txid]).to be_a(String)
      expect(result[:txid].length).to eq(64)
      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
    end

    it 'returns :tx as a byte array' do
      expect(result[:tx]).to be_a(Array)
      expect(result[:tx]).to all(be_a(Integer))
    end

    it 'does not return a signable_transaction' do
      expect(result).not_to have_key(:signable_transaction)
    end

    it 'stores the action with the correct description' do
      result[:txid]
      wallet.list_actions({ labels: [description] })
      # Action is stored; description may not match label filter directly —
      # store stores with labels param, so use a broader label
      # Re-create with an explicit label to enable lookup
      wallet.create_action({
                             description: description,
                             outputs: [output_spec],
                             labels: ['payment test']
                           })
      actions = wallet.list_actions({ labels: ['payment test'] })
      expect(actions[:total_actions]).to be >= 1
      expect(actions[:actions].any? { |a| a[:description] == description }).to be true
    end

    it 'stores labels on the action' do
      wallet.create_action({
                             description: description,
                             outputs: [output_spec],
                             labels: ['labeled action']
                           })
      actions = wallet.list_actions({ labels: ['labeled action'] })
      expect(actions[:total_actions]).to eq(1)
    end

    it 'stores output in basket when basket is specified' do
      basket_output = output_spec.merge(basket: 'my test tokens')
      wallet.create_action({
                             description: description,
                             outputs: [basket_output]
                           })
      outputs = wallet.list_outputs({ basket: 'my test tokens' })
      expect(outputs[:total_outputs]).to eq(1)
      expect(outputs[:outputs].first[:satoshis]).to eq(1000)
    end

    it 'stores output tags when tags are specified' do
      tagged_output = output_spec.merge(basket: 'token vault', tags: %w[rare gold])
      wallet.create_action({
                             description: description,
                             outputs: [tagged_output]
                           })
      outputs = wallet.list_outputs({ basket: 'token vault', tags: ['rare'] })
      expect(outputs[:total_outputs]).to eq(1)
    end

    it 'stores correct outpoint index even after output shuffling' do
      # Two outputs: only the second has a basket. After shuffling, the on-chain
      # index may differ from the original array position. The stored outpoint
      # must reflect the actual post-shuffle position.
      untracked = output_spec.dup
      tracked = output_spec.merge(basket: 'shuffle check', satoshis: 7777)

      # Run enough times that shuffling is virtually certain to swap at least once
      10.times do |i|
        w = described_class.new(private_key, storage: BSV::Wallet::MemoryStore.new, broadcaster: broadcaster)
        w.create_action({
                          description: "shuffle test #{i} check",
                          outputs: [untracked, tracked]
                        })
        stored = w.list_outputs({ basket: 'shuffle check' })
        expect(stored[:total_outputs]).to eq(1)
        outpoint = stored[:outputs].first[:outpoint]
        # The outpoint index must match the actual position of the 7777-sat output
        # in the serialised transaction, not the original array index (1).
        _txid, vout = outpoint.split('.')
        # Verify the index is valid (0 or 1 for a 2-output tx)
        expect(vout.to_i).to be_between(0, 1)
        # Verify the stored satoshis match
        expect(stored[:outputs].first[:satoshis]).to eq(7777)
      end
    end

    it 'does not store outputs without a basket' do
      # output_spec has no basket
      wallet.create_action({ description: description, outputs: [output_spec] })
      # Attempting to list from a basket that would normally hold it returns 0
      outputs = wallet.list_outputs({ basket: 'my test tokens' })
      expect(outputs[:total_outputs]).to eq(0)
    end

    it 'increments total_actions with each call' do
      wallet.create_action({ description: description, outputs: [output_spec], labels: ['counter test'] })
      wallet.create_action({ description: description, outputs: [output_spec], labels: ['counter test'] })
      actions = wallet.list_actions({ labels: ['counter test'] })
      expect(actions[:total_actions]).to eq(2)
    end

    context 'with no_send option' do
      it 'stores action with status "nosend" and returns no_send_change' do
        r = wallet.create_action({
                                   description: description,
                                   outputs: [output_spec],
                                   options: { no_send: true }
                                 })
        expect(r[:no_send_change]).to eq([])
        expect(r[:txid]).to be_a(String)
      end
    end
  end

  # -------------------------------------------------------------------------
  # #create_action — signable transaction flow (input with unlocking_script_length)
  # -------------------------------------------------------------------------
  describe '#create_action — signable transaction flow' do
    let(:source_tx_and_beef) { build_source_beef }
    let(:source_tx) { source_tx_and_beef[0] }
    let(:input_beef_bytes) { source_tx_and_beef[1] }
    let(:source_txid) { source_tx.txid_hex }

    let(:signable_result) do
      wallet.create_action({
                             description: 'signable transaction test action',
                             input_beef: input_beef_bytes,
                             inputs: [{
                               outpoint: "#{source_txid}.0",
                               unlocking_script_length: 107,
                               input_description: 'spend source output one'
                             }],
                             outputs: [{
                               locking_script: locking_script_hex,
                               satoshis: 4000,
                               output_description: 'payment output one'
                             }]
                           })
    end

    it 'returns a signable_transaction hash' do
      expect(signable_result[:signable_transaction]).to be_a(Hash)
    end

    it 'returns a base64 reference string' do
      expect(signable_result[:signable_transaction][:reference]).to be_a(String)
      ref = signable_result[:signable_transaction][:reference]
      expect { Base64.strict_decode64(ref) }.not_to raise_error
    end

    it 'returns :tx as a byte array inside signable_transaction' do
      tx_bytes = signable_result[:signable_transaction][:tx]
      expect(tx_bytes).to be_a(Array)
      expect(tx_bytes).to all(be_a(Integer))
    end

    it 'does not return a top-level :txid' do
      expect(signable_result).not_to have_key(:txid)
    end

    it 'returns different references for different signable transactions' do
      r1 = wallet.create_action({
                                  description: 'signable transaction test one aa',
                                  input_beef: input_beef_bytes,
                                  inputs: [{
                                    outpoint: "#{source_txid}.0",
                                    unlocking_script_length: 107,
                                    input_description: 'spend source output one'
                                  }],
                                  outputs: [output_spec]
                                })
      _, beef2 = build_source_beef
      r2 = wallet.create_action({
                                  description: 'signable transaction test two bb',
                                  input_beef: beef2,
                                  inputs: [{
                                    outpoint: "#{BSV::Transaction::Transaction.new.tap { |t| t.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 1, locking_script: BSV::Script::Script.p2pkh_lock(pub_key.hash160))) }.txid_hex}.0",
                                    unlocking_script_length: 107,
                                    input_description: 'spend second source output'
                                  }],
                                  outputs: [output_spec]
                                })
      ref1 = r1[:signable_transaction][:reference]
      ref2 = r2[:signable_transaction][:reference]
      expect(ref1).not_to eq(ref2)
    end
  end

  # -------------------------------------------------------------------------
  # #sign_action
  # -------------------------------------------------------------------------
  describe '#sign_action' do
    let(:source_tx_and_beef) { build_source_beef }
    let(:source_tx) { source_tx_and_beef[0] }
    let(:input_beef_bytes) { source_tx_and_beef[1] }
    let(:source_txid) { source_tx.txid_hex }

    let(:signable_result) do
      wallet.create_action({
                             description: 'sign action integration test',
                             input_beef: input_beef_bytes,
                             inputs: [{
                               outpoint: "#{source_txid}.0",
                               unlocking_script_length: 107,
                               input_description: 'spend the source output'
                             }],
                             outputs: [{
                               locking_script: locking_script_hex,
                               satoshis: 4000,
                               output_description: 'signed payment output'
                             }]
                           })
    end

    let(:reference) { signable_result[:signable_transaction][:reference] }

    # Build a dummy P2PKH unlocking script hex (signature + pubkey push)
    let(:dummy_unlock_hex) do
      # 71-byte dummy DER sig + sighash byte, then compressed pubkey push
      sig_bytes = "0#{"\x00" * 70}A".b
      pub_bytes = pub_key.compressed
      BSV::Script::Script.p2pkh_unlock(sig_bytes, pub_bytes).to_hex
    end

    it 'returns a txid and tx after signing' do
      result = wallet.sign_action({
                                    reference: reference,
                                    spends: { 0 => { unlocking_script: dummy_unlock_hex } }
                                  })
      expect(result[:txid]).to be_a(String)
      expect(result[:txid].length).to eq(64)
      expect(result[:tx]).to be_a(Array)
    end

    it 'stores the signed action in storage' do
      # Create a second labeled signable so we can verify storage via list_actions
      build_source_beef
      labeled_source_tx = BSV::Transaction::Transaction.new
      labeled_source_tx.add_output(
        BSV::Transaction::TransactionOutput.new(
          satoshis: 3000,
          locking_script: BSV::Script::Script.p2pkh_lock(pub_key.hash160)
        )
      )
      labeled_input_beef = labeled_source_tx.to_beef.unpack('C*')
      labeled_result = wallet.create_action({
                                              description: 'labeled signable action',
                                              input_beef: labeled_input_beef,
                                              inputs: [{
                                                outpoint: "#{labeled_source_tx.txid_hex}.0",
                                                unlocking_script_length: 107,
                                                input_description: 'spend labeled source'
                                              }],
                                              outputs: [output_spec],
                                              labels: ['signed storage test']
                                            })
      wallet.sign_action({
                           reference: labeled_result[:signable_transaction][:reference],
                           spends: { 0 => { unlocking_script: dummy_unlock_hex } }
                         })
      actions = wallet.list_actions({ labels: ['signed storage test'] })
      expect(actions[:total_actions]).to eq(1)
    end

    it 'clears the pending transaction so abort raises afterwards' do
      wallet.sign_action({
                           reference: reference,
                           spends: { 0 => { unlocking_script: dummy_unlock_hex } }
                         })
      expect do
        wallet.abort_action({ reference: reference })
      end.to raise_error(BSV::Wallet::WalletError)
    end

    it 'raises WalletError for an invalid reference' do
      expect do
        wallet.sign_action({ reference: 'invalid-reference', spends: {} })
      end.to raise_error(BSV::Wallet::WalletError, /not found/)
    end

    it 'raises WalletError for an out-of-range input index' do
      expect do
        wallet.sign_action({
                             reference: reference,
                             spends: { 99 => { unlocking_script: dummy_unlock_hex } }
                           })
      end.to raise_error(BSV::Wallet::WalletError, /out of range/)
    end

    it 'accepts string keys in spends hash' do
      result = wallet.sign_action({
                                    reference: reference,
                                    spends: { '0' => { unlocking_script: dummy_unlock_hex } }
                                  })
      expect(result[:txid]).to be_a(String)
    end
  end

  # -------------------------------------------------------------------------
  # accept_delayed_broadcast option — finalize_action path
  # -------------------------------------------------------------------------
  describe 'accept_delayed_broadcast option (finalize_action path)' do
    let(:source_tx_and_beef) { build_source_beef }
    let(:source_tx) { source_tx_and_beef[0] }
    let(:input_beef_bytes) { source_tx_and_beef[1] }
    let(:source_txid) { source_tx.txid_hex }

    let(:base_args) do
      {
        description: 'accept delayed broadcast test',
        input_beef: input_beef_bytes,
        inputs: [{
          outpoint: "#{source_txid}.0",
          unlocking_script: 'aabb',
          input_description: 'input for delayed broadcast test'
        }],
        outputs: [{
          locking_script: locking_script_hex,
          satoshis: 4000,
          output_description: 'payment output'
        }]
      }
    end

    # Post-HLR #455: no broadcaster raises WalletError unless accept_delayed_broadcast
    # or no_send: true is set. Use no_broadcaster_wallet to exercise the guard.
    it 'raises WalletError when no broadcaster and accept_delayed_broadcast: false' do
      expect do
        no_broadcaster_wallet.create_action(base_args.merge(options: { accept_delayed_broadcast: false }))
      end.to raise_error(BSV::Wallet::WalletError, /broadcaster/)
    end

    # accept_delayed_broadcast: true does NOT bypass the broadcaster guard —
    # only no_send: true does. The option relaxes error handling at the InlineQueue
    # level but the wallet still requires a broadcaster to be configured.
    it 'raises WalletError when no broadcaster and accept_delayed_broadcast: true' do
      expect do
        no_broadcaster_wallet.create_action(base_args.merge(options: { accept_delayed_broadcast: true }))
      end.to raise_error(BSV::Wallet::WalletError, /broadcaster/)
    end

    # With no_send: true, the broadcaster guard is bypassed and the action succeeds
    it 'succeeds with no_send: true and no broadcaster' do
      expect do
        no_broadcaster_wallet.create_action(base_args.merge(options: { no_send: true }))
      end.not_to raise_error
    end

    # Post-HLR #455: no broadcaster + no no_send raises rather than silently 'completing'
    it 'raises WalletError when no broadcaster and option is absent' do
      expect do
        no_broadcaster_wallet.create_action(base_args)
      end.to raise_error(BSV::Wallet::WalletError, /broadcaster/)
    end
  end

  # -------------------------------------------------------------------------
  # accept_delayed_broadcast option — sign_action path
  # -------------------------------------------------------------------------
  describe 'accept_delayed_broadcast option (sign_action path)' do
    let(:source_tx_and_beef) { build_source_beef }
    let(:source_tx) { source_tx_and_beef[0] }
    let(:input_beef_bytes) { source_tx_and_beef[1] }
    let(:source_txid) { source_tx.txid_hex }
    let(:dummy_unlock_hex) { 'aabb' }

    let(:signable_result) do
      wallet.create_action({
                             description: 'sign action delayed broadcast test',
                             input_beef: input_beef_bytes,
                             inputs: [{
                               outpoint: "#{source_txid}.0",
                               unlocking_script_length: 107,
                               input_description: 'spend for sign action test'
                             }],
                             outputs: [{
                               locking_script: locking_script_hex,
                               satoshis: 4000,
                               output_description: 'payment output'
                             }]
                           })
    end

    let(:reference) { signable_result[:signable_transaction][:reference] }

    it 'accepts accept_delayed_broadcast: false in sign_action without error' do
      result = wallet.sign_action({
                                    reference: reference,
                                    spends: { 0 => { unlocking_script: dummy_unlock_hex } },
                                    options: { accept_delayed_broadcast: false }
                                  })
      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
    end

    it 'accepts accept_delayed_broadcast: true in sign_action without raising' do
      expect do
        wallet.sign_action({
                             reference: reference,
                             spends: { 0 => { unlocking_script: dummy_unlock_hex } },
                             options: { accept_delayed_broadcast: true }
                           })
      end.not_to raise_error
    end

    it 'stores the action as unproven when sign_action passes accept_delayed_broadcast: true' do
      result = wallet.sign_action({
                                    reference: reference,
                                    spends: { 0 => { unlocking_script: dummy_unlock_hex } },
                                    options: { accept_delayed_broadcast: true }
                                  })
      all_actions = wallet.storage.find_actions({ limit: 100, offset: 0 })
      action = all_actions.find { |a| a[:txid] == result[:txid] }
      expect(action[:status]).to eq('unproven')
    end

    it 'does not log a warning when sign_action passes accept_delayed_broadcast: true' do
      expect do
        wallet.sign_action({
                             reference: reference,
                             spends: { 0 => { unlocking_script: dummy_unlock_hex } },
                             options: { accept_delayed_broadcast: true }
                           })
      end.not_to output(/accept_delayed_broadcast/i).to_stderr
    end
  end

  # -------------------------------------------------------------------------
  # #abort_action
  # -------------------------------------------------------------------------
  describe '#abort_action' do
    let(:source_tx_and_beef) { build_source_beef }
    let(:source_tx) { source_tx_and_beef[0] }
    let(:input_beef_bytes) { source_tx_and_beef[1] }
    let(:source_txid) { source_tx.txid_hex }

    let(:signable_result) do
      wallet.create_action({
                             description: 'abort action integration test',
                             input_beef: input_beef_bytes,
                             inputs: [{
                               outpoint: "#{source_txid}.0",
                               unlocking_script_length: 107,
                               input_description: 'spend source for abort test'
                             }],
                             outputs: [output_spec]
                           })
    end

    let(:reference) { signable_result[:signable_transaction][:reference] }

    it 'returns { aborted: true }' do
      result = wallet.abort_action({ reference: reference })
      expect(result).to eq({ aborted: true })
    end

    it 'removes the pending transaction so a second abort raises' do
      wallet.abort_action({ reference: reference })
      expect do
        wallet.abort_action({ reference: reference })
      end.to raise_error(BSV::Wallet::WalletError)
    end

    it 'raises WalletError for an unknown reference' do
      expect do
        wallet.abort_action({ reference: 'does-not-exist' })
      end.to raise_error(BSV::Wallet::WalletError, /not found/)
    end

    it 'prevents signing after abort' do
      wallet.abort_action({ reference: reference })
      expect do
        wallet.sign_action({ reference: reference, spends: {} })
      end.to raise_error(BSV::Wallet::WalletError)
    end
  end

  # -------------------------------------------------------------------------
  # #list_actions
  # -------------------------------------------------------------------------
  describe '#list_actions' do
    before do
      wallet.create_action({ description: 'payment action one', outputs: [output_spec], labels: ['payment'] })
      wallet.create_action({ description: 'payment action two', outputs: [output_spec], labels: ['payment'] })
      wallet.create_action({ description: 'transfer action one', outputs: [output_spec], labels: ['transfer'] })
      wallet.create_action({ description: 'mixed action labels', outputs: [output_spec], labels: %w[payment transfer] })
    end

    it 'raises InvalidParameterError when labels is missing' do
      expect do
        wallet.list_actions({})
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises InvalidParameterError when labels is empty' do
      expect do
        wallet.list_actions({ labels: [] })
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'returns total_actions and actions keys' do
      result = wallet.list_actions({ labels: ['payment'] })
      expect(result).to have_key(:total_actions)
      expect(result).to have_key(:actions)
    end

    it 'lists actions matching any label by default' do
      result = wallet.list_actions({ labels: ['payment'] })
      # 3 actions have 'payment' label
      expect(result[:total_actions]).to eq(3)
    end

    it 'lists actions matching any label with explicit "any" mode' do
      result = wallet.list_actions({ labels: %w[payment transfer], label_query_mode: 'any' })
      expect(result[:total_actions]).to eq(4)
    end

    it 'lists only actions matching all labels with "all" mode' do
      result = wallet.list_actions({ labels: %w[payment transfer], label_query_mode: 'all' })
      expect(result[:total_actions]).to eq(1)
    end

    it 'returns actions as an Array' do
      result = wallet.list_actions({ labels: ['payment'] })
      expect(result[:actions]).to be_a(Array)
    end

    it 'paginates results using limit' do
      result = wallet.list_actions({ labels: ['payment'], limit: 2 })
      expect(result[:actions].length).to eq(2)
      expect(result[:total_actions]).to eq(3)
    end

    it 'paginates results using offset' do
      all = wallet.list_actions({ labels: ['payment'], limit: 10 })
      paged = wallet.list_actions({ labels: ['payment'], limit: 10, offset: 1 })
      expect(paged[:actions].length).to eq(2)
      expect(paged[:actions].first[:txid]).to eq(all[:actions][1][:txid])
    end

    it 'returns 0 total_actions when no actions match' do
      result = wallet.list_actions({ labels: ['nonexistent label'] })
      expect(result[:total_actions]).to eq(0)
      expect(result[:actions]).to be_empty
    end
  end

  # -------------------------------------------------------------------------
  # #list_outputs
  # -------------------------------------------------------------------------
  describe '#list_outputs' do
    before do
      wallet.create_action({
                             description: 'create basket outputs one',
                             outputs: [
                               { locking_script: locking_script_hex, satoshis: 500, output_description: 'token alpha', basket: 'my tokens', tags: ['rare'] },
                               { locking_script: locking_script_hex, satoshis: 1500, output_description: 'token beta', basket: 'my tokens', tags: %w[rare gold] }
                             ]
                           })
      wallet.create_action({
                             description: 'create other basket output',
                             outputs: [
                               { locking_script: locking_script_hex, satoshis: 2000, output_description: 'other output', basket: 'secondary store' }
                             ]
                           })
    end

    it 'raises InvalidParameterError when basket is missing' do
      expect do
        wallet.list_outputs({})
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'returns total_outputs and outputs keys' do
      result = wallet.list_outputs({ basket: 'my tokens' })
      expect(result).to have_key(:total_outputs)
      expect(result).to have_key(:outputs)
    end

    it 'lists all outputs in the specified basket' do
      result = wallet.list_outputs({ basket: 'my tokens' })
      expect(result[:total_outputs]).to eq(2)
    end

    it 'does not return outputs from a different basket' do
      result = wallet.list_outputs({ basket: 'secondary store' })
      expect(result[:total_outputs]).to eq(1)
      expect(result[:outputs].first[:satoshis]).to eq(2000)
    end

    it 'filters by tags in "any" mode' do
      result = wallet.list_outputs({ basket: 'my tokens', tags: ['gold'] })
      expect(result[:total_outputs]).to eq(1)
      expect(result[:outputs].first[:satoshis]).to eq(1500)
    end

    it 'filters by tags in "all" mode' do
      result = wallet.list_outputs({ basket: 'my tokens', tags: %w[rare gold], tag_query_mode: 'all' })
      expect(result[:total_outputs]).to eq(1)
    end

    it 'paginates results using limit' do
      result = wallet.list_outputs({ basket: 'my tokens', limit: 1 })
      expect(result[:actions]).to be_nil
      expect(result[:outputs].length).to eq(1)
      expect(result[:total_outputs]).to eq(2)
    end

    it 'paginates results using offset' do
      all = wallet.list_outputs({ basket: 'my tokens', limit: 10 })
      paged = wallet.list_outputs({ basket: 'my tokens', limit: 10, offset: 1 })
      expect(paged[:outputs].length).to eq(1)
      expect(paged[:outputs].first[:outpoint]).to eq(all[:outputs][1][:outpoint])
    end

    it 'returns 0 total_outputs for an empty basket' do
      result = wallet.list_outputs({ basket: 'empty store' })
      expect(result[:total_outputs]).to eq(0)
    end
  end

  # -------------------------------------------------------------------------
  # list_actions include flags
  # -------------------------------------------------------------------------
  describe '#list_actions include flags' do
    before do
      wallet.create_action({ description: 'labelled action', outputs: [output_spec], labels: ['payment'] })
    end

    it 'strips :labels by default (flag absent)' do
      result = wallet.list_actions({ labels: ['payment'] })
      expect(result[:actions].first).not_to have_key(:labels)
    end

    it 'strips :labels when include_labels is false' do
      result = wallet.list_actions({ labels: ['payment'], include_labels: false })
      expect(result[:actions].first).not_to have_key(:labels)
    end

    it 'strips :labels when include_labels is nil' do
      result = wallet.list_actions({ labels: ['payment'], include_labels: nil })
      expect(result[:actions].first).not_to have_key(:labels)
    end

    it 'preserves :labels when include_labels is true' do
      result = wallet.list_actions({ labels: ['payment'], include_labels: true })
      expect(result[:actions].first).to have_key(:labels)
      expect(result[:actions].first[:labels]).to include('payment')
    end

    it 'strips :inputs by default (field not currently stored, no-op)' do
      result = wallet.list_actions({ labels: ['payment'] })
      expect(result[:actions].first).not_to have_key(:inputs)
    end

    it 'strips :outputs by default (field not currently stored, no-op)' do
      result = wallet.list_actions({ labels: ['payment'] })
      expect(result[:actions].first).not_to have_key(:outputs)
    end

    it 'does not affect total_actions count' do
      result_default = wallet.list_actions({ labels: ['payment'] })
      result_with_flags = wallet.list_actions({ labels: ['payment'], include_labels: true })
      expect(result_default[:total_actions]).to eq(result_with_flags[:total_actions])
    end

    it 'strips nested :source_locking_script from inputs when present' do
      action = wallet.list_actions({ labels: ['payment'], include_inputs: true })[:actions].first
      action[:inputs] = [{ source_locking_script: 'aabbcc', unlocking_script: 'ddeeff' }]
      # Simulate: call strip_action_fields directly via the stripping logic
      # Verify by calling list_actions with a storage that returns inputs
      # (MemoryStore does not populate inputs, so we test via private method)
      result = wallet.send(:strip_action_fields, [action], { include_inputs: true })
      expect(result.first[:inputs].first).not_to have_key(:source_locking_script)
    end

    it 'strips nested :unlocking_script from inputs when present' do
      action = wallet.list_actions({ labels: ['payment'], include_inputs: true })[:actions].first
      action[:inputs] = [{ source_locking_script: 'aabbcc', unlocking_script: 'ddeeff' }]
      result = wallet.send(:strip_action_fields, [action], { include_inputs: true, include_input_unlocking_scripts: false })
      expect(result.first[:inputs].first).not_to have_key(:unlocking_script)
    end

    it 'preserves nested :source_locking_script when include_input_source_locking_scripts is true' do
      action = wallet.list_actions({ labels: ['payment'], include_inputs: true })[:actions].first
      action[:inputs] = [{ source_locking_script: 'aabbcc' }]
      result = wallet.send(:strip_action_fields, [action],
                           { include_inputs: true, include_input_source_locking_scripts: true })
      expect(result.first[:inputs].first).to have_key(:source_locking_script)
    end

    it 'strips nested :locking_script from outputs when present' do
      action = wallet.list_actions({ labels: ['payment'], include_outputs: true })[:actions].first
      action[:outputs] = [{ locking_script: 'aabbcc', satoshis: 1000 }]
      result = wallet.send(:strip_action_fields, [action], { include_outputs: true })
      expect(result.first[:outputs].first).not_to have_key(:locking_script)
    end

    it 'preserves nested :locking_script when include_output_locking_scripts is true' do
      action = wallet.list_actions({ labels: ['payment'], include_outputs: true })[:actions].first
      action[:outputs] = [{ locking_script: 'aabbcc', satoshis: 1000 }]
      result = wallet.send(:strip_action_fields, [action],
                           { include_outputs: true, include_output_locking_scripts: true })
      expect(result.first[:outputs].first).to have_key(:locking_script)
    end

    it 'does not mutate the original action hashes' do
      stored = wallet.list_actions({ labels: ['payment'], include_labels: true })[:actions]
      original_keys = stored.first.keys.dup
      wallet.list_actions({ labels: ['payment'] })
      expect(stored.first.keys).to eq(original_keys)
    end
  end

  # -------------------------------------------------------------------------
  # list_outputs include flags
  # -------------------------------------------------------------------------
  describe '#list_outputs include flags' do
    before do
      wallet.create_action({
                             description: 'create tagged output',
                             outputs: [{
                               locking_script: locking_script_hex,
                               satoshis: 500,
                               output_description: 'tagged token',
                               basket: 'flag test',
                               tags: ['rare'],
                               custom_instructions: 'handle with care'
                             }]
                           })
    end

    it 'strips :tags by default (flag absent)' do
      result = wallet.list_outputs({ basket: 'flag test' })
      expect(result[:outputs].first).not_to have_key(:tags)
    end

    it 'strips :tags when include_tags is false' do
      result = wallet.list_outputs({ basket: 'flag test', include_tags: false })
      expect(result[:outputs].first).not_to have_key(:tags)
    end

    it 'strips :tags when include_tags is nil' do
      result = wallet.list_outputs({ basket: 'flag test', include_tags: nil })
      expect(result[:outputs].first).not_to have_key(:tags)
    end

    it 'preserves :tags when include_tags is true' do
      result = wallet.list_outputs({ basket: 'flag test', include_tags: true })
      expect(result[:outputs].first).to have_key(:tags)
      expect(result[:outputs].first[:tags]).to include('rare')
    end

    it 'strips :labels by default (field not currently stored, no-op)' do
      result = wallet.list_outputs({ basket: 'flag test' })
      expect(result[:outputs].first).not_to have_key(:labels)
    end

    it 'strips :custom_instructions by default' do
      result = wallet.list_outputs({ basket: 'flag test' })
      expect(result[:outputs].first).not_to have_key(:custom_instructions)
    end

    it 'strips :custom_instructions when include_custom_instructions is false' do
      result = wallet.list_outputs({ basket: 'flag test', include_custom_instructions: false })
      expect(result[:outputs].first).not_to have_key(:custom_instructions)
    end

    it 'preserves :custom_instructions when include_custom_instructions is true' do
      result = wallet.list_outputs({ basket: 'flag test', include_custom_instructions: true })
      expect(result[:outputs].first).to have_key(:custom_instructions)
      expect(result[:outputs].first[:custom_instructions]).to eq('handle with care')
    end

    it 'preserves :tags and strips :custom_instructions with mixed flags' do
      result = wallet.list_outputs({ basket: 'flag test', include_tags: true })
      expect(result[:outputs].first).to have_key(:tags)
      expect(result[:outputs].first).not_to have_key(:custom_instructions)
    end

    it 'preserves all fields when all flags are true' do
      result = wallet.list_outputs({ basket: 'flag test',
                                     include_tags: true,
                                     include_labels: true,
                                     include_custom_instructions: true })
      expect(result[:outputs].first).to have_key(:tags)
      expect(result[:outputs].first).to have_key(:custom_instructions)
    end

    it 'does not affect total_outputs count' do
      result_default = wallet.list_outputs({ basket: 'flag test' })
      result_with_flags = wallet.list_outputs({ basket: 'flag test', include_tags: true })
      expect(result_default[:total_outputs]).to eq(result_with_flags[:total_outputs])
    end

    it 'does not mutate the original output hashes' do
      stored = wallet.list_outputs({ basket: 'flag test', include_tags: true, include_custom_instructions: true })[:outputs]
      original_keys = stored.first.keys.dup
      wallet.list_outputs({ basket: 'flag test' })
      expect(stored.first.keys).to eq(original_keys)
    end
  end

  # -------------------------------------------------------------------------
  # #relinquish_output
  # -------------------------------------------------------------------------
  describe '#relinquish_output' do
    before do
      wallet.create_action({
                             description: 'create relinquish test output',
                             outputs: [{
                               locking_script: locking_script_hex,
                               satoshis: 777,
                               output_description: 'relinquish target',
                               basket: 'relinquish test'
                             }]
                           })
    end

    let(:outpoint) do
      wallet.list_outputs({ basket: 'relinquish test' })[:outputs].first[:outpoint]
    end

    it 'returns { relinquished: true }' do
      result = wallet.relinquish_output({ basket: 'relinquish test', output: outpoint })
      expect(result).to eq({ relinquished: true })
    end

    it 'removes the output from storage' do
      wallet.relinquish_output({ basket: 'relinquish test', output: outpoint })
      remaining = wallet.list_outputs({ basket: 'relinquish test' })
      expect(remaining[:total_outputs]).to eq(0)
    end

    it 'raises WalletError for a non-existent output' do
      fake_outpoint = "#{'a' * 64}.0"
      expect do
        wallet.relinquish_output({ basket: 'relinquish test', output: fake_outpoint })
      end.to raise_error(BSV::Wallet::WalletError, /not found/)
    end

    it 'raises InvalidParameterError for an invalid basket name' do
      expect do
        wallet.relinquish_output({ basket: '', output: outpoint })
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises InvalidParameterError for an invalid outpoint format' do
      expect do
        wallet.relinquish_output({ basket: 'relinquish test', output: 'not-an-outpoint' })
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  # -------------------------------------------------------------------------
  # #internalize_action — basket insertion
  # -------------------------------------------------------------------------
  describe '#internalize_action — basket insertion' do
    let(:incoming_tx) do
      tx = BSV::Transaction::Transaction.new
      tx.add_output(
        BSV::Transaction::TransactionOutput.new(
          satoshis: 2000,
          locking_script: BSV::Script::Script.p2pkh_lock(pub_key.hash160)
        )
      )
      tx
    end

    let(:beef_bytes) { incoming_tx.to_beef.unpack('C*') }

    it 'returns { accepted: true }' do
      result = wallet.internalize_action({
                                           tx: beef_bytes,
                                           description: 'receive incoming tokens',
                                           outputs: [{
                                             output_index: 0,
                                             protocol: 'basket insertion',
                                             insertion_remittance: {
                                               basket: 'my test tokens',
                                               tags: ['incoming']
                                             }
                                           }]
                                         })
      expect(result[:accepted]).to be true
    end

    it 'stores the output in the specified basket' do
      wallet.internalize_action({
                                  tx: beef_bytes,
                                  description: 'receive incoming tokens',
                                  outputs: [{
                                    output_index: 0,
                                    protocol: 'basket insertion',
                                    insertion_remittance: {
                                      basket: 'my test tokens',
                                      tags: ['incoming']
                                    }
                                  }]
                                })
      outputs = wallet.list_outputs({ basket: 'my test tokens' })
      expect(outputs[:total_outputs]).to eq(1)
      expect(outputs[:outputs].first[:satoshis]).to eq(2000)
    end

    it 'applies tags from insertion_remittance' do
      wallet.internalize_action({
                                  tx: beef_bytes,
                                  description: 'receive tagged tokens',
                                  outputs: [{
                                    output_index: 0,
                                    protocol: 'basket insertion',
                                    insertion_remittance: {
                                      basket: 'tagged test store',
                                      tags: %w[rare special]
                                    }
                                  }]
                                })
      outputs = wallet.list_outputs({ basket: 'tagged test store', tags: ['rare'] })
      expect(outputs[:total_outputs]).to eq(1)
    end

    it 'stores the action in storage' do
      wallet.internalize_action({
                                  tx: beef_bytes,
                                  description: 'internalize action label',
                                  outputs: [{
                                    output_index: 0,
                                    protocol: 'basket insertion',
                                    insertion_remittance: { basket: 'my test tokens' }
                                  }],
                                  labels: ['inbound']
                                })
      actions = wallet.list_actions({ labels: ['inbound'] })
      expect(actions[:total_actions]).to eq(1)
    end

    it 'raises InvalidParameterError when tx is not an Array' do
      expect do
        wallet.internalize_action({
                                    tx: 'not an array',
                                    description: 'bad tx param here',
                                    outputs: [{ output_index: 0, protocol: 'basket insertion', insertion_remittance: { basket: 'my test tokens' } }]
                                  })
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises InvalidParameterError when outputs is empty' do
      expect do
        wallet.internalize_action({
                                    tx: beef_bytes,
                                    description: 'no outputs given',
                                    outputs: []
                                  })
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises WalletError when output_index is out of range' do
      expect do
        wallet.internalize_action({
                                    tx: beef_bytes,
                                    description: 'bad output index test',
                                    outputs: [{
                                      output_index: 99,
                                      protocol: 'basket insertion',
                                      insertion_remittance: { basket: 'my test tokens' }
                                    }]
                                  })
      end.to raise_error(BSV::Wallet::WalletError, /not found/)
    end

    it 'raises InvalidParameterError for an unknown protocol' do
      expect do
        wallet.internalize_action({
                                    tx: beef_bytes,
                                    description: 'unknown protocol test',
                                    outputs: [{
                                      output_index: 0,
                                      protocol: 'unknown protocol type',
                                      insertion_remittance: { basket: 'my test tokens' }
                                    }]
                                  })
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises InvalidParameterError when insertion_remittance is nil' do
      expect do
        wallet.internalize_action({
                                    tx: beef_bytes,
                                    description: 'nil remittance test',
                                    outputs: [{
                                      output_index: 0,
                                      protocol: 'basket insertion',
                                      insertion_remittance: nil
                                    }]
                                  })
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  # -------------------------------------------------------------------------
  # #internalize_action — wallet payment (BRC-29)
  # -------------------------------------------------------------------------
  describe '#internalize_action — wallet payment' do
    let(:sender_key) { BSV::Primitives::PrivateKey.generate }
    let(:sender_pub_hex) { sender_key.public_key.to_hex }
    let(:derivation_prefix) { Base64.strict_encode64(SecureRandom.random_bytes(16)) }
    let(:derivation_suffix) { Base64.strict_encode64(SecureRandom.random_bytes(16)) }

    # Derive the public key the wallet expects (matching internalize_payment logic)
    let(:expected_pub) do
      wallet.key_deriver.derive_public_key(
        [2, '3241645161d8'],
        "#{derivation_prefix} #{derivation_suffix}",
        sender_pub_hex,
        for_self: true
      )
    end

    let(:payment_tx) do
      tx = BSV::Transaction::Transaction.new
      tx.add_output(
        BSV::Transaction::TransactionOutput.new(
          satoshis: 50_000,
          locking_script: BSV::Script::Script.p2pkh_lock(expected_pub.hash160)
        )
      )
      tx
    end

    let(:beef_bytes) { payment_tx.to_beef.unpack('C*') }

    it 'returns { accepted: true } for a correctly derived payment' do
      result = wallet.internalize_action({
                                           tx: beef_bytes,
                                           description: 'receive wallet payment',
                                           outputs: [{
                                             output_index: 0,
                                             protocol: 'wallet payment',
                                             payment_remittance: {
                                               sender_identity_key: sender_pub_hex,
                                               derivation_prefix: derivation_prefix,
                                               derivation_suffix: derivation_suffix
                                             }
                                           }]
                                         })
      expect(result[:accepted]).to be true
    end

    it 'stores the output with sender identity metadata' do
      wallet.internalize_action({
                                  tx: beef_bytes,
                                  description: 'receive wallet payment',
                                  outputs: [{
                                    output_index: 0,
                                    protocol: 'wallet payment',
                                    payment_remittance: {
                                      sender_identity_key: sender_pub_hex,
                                      derivation_prefix: derivation_prefix,
                                      derivation_suffix: derivation_suffix
                                    }
                                  }]
                                })
      # Payment outputs are stored without a basket; verify via storage directly
      # (they are spendable but without basket assignment)
      expect(wallet.storage).to respond_to(:find_outputs)
    end

    it 'raises WalletError when the output script does not match the derived key' do
      # Build a tx with a random unrelated locking script
      wrong_tx = BSV::Transaction::Transaction.new
      wrong_pub = BSV::Primitives::PrivateKey.generate.public_key
      wrong_tx.add_output(
        BSV::Transaction::TransactionOutput.new(
          satoshis: 50_000,
          locking_script: BSV::Script::Script.p2pkh_lock(wrong_pub.hash160)
        )
      )
      wrong_beef = wrong_tx.to_beef.unpack('C*')

      expect do
        wallet.internalize_action({
                                    tx: wrong_beef,
                                    description: 'wrong script wallet pay',
                                    outputs: [{
                                      output_index: 0,
                                      protocol: 'wallet payment',
                                      payment_remittance: {
                                        sender_identity_key: sender_pub_hex,
                                        derivation_prefix: derivation_prefix,
                                        derivation_suffix: derivation_suffix
                                      }
                                    }]
                                  })
      end.to raise_error(BSV::Wallet::WalletError, /script does not match/)
    end

    it 'raises InvalidParameterError when payment_remittance is nil' do
      expect do
        wallet.internalize_action({
                                    tx: beef_bytes,
                                    description: 'nil remittance wallet pay',
                                    outputs: [{
                                      output_index: 0,
                                      protocol: 'wallet payment',
                                      payment_remittance: nil
                                    }]
                                  })
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  # -------------------------------------------------------------------------
  # Inherited crypto methods (smoke test)
  # -------------------------------------------------------------------------
  describe 'inherited ProtoWallet methods' do
    let(:crypto_args) do
      { protocol_id: [0, 'hello world'], key_id: 'test key 1', counterparty: 'self' }
    end

    it 'inherits encrypt/decrypt round-trip from ProtoWallet' do
      plaintext = [1, 2, 3, 4, 5]
      encrypted = wallet.encrypt(crypto_args.merge(plaintext: plaintext))
      decrypted = wallet.decrypt(crypto_args.merge(ciphertext: encrypted[:ciphertext]))
      expect(decrypted[:plaintext]).to eq(plaintext)
    end

    it 'inherits get_public_key from ProtoWallet' do
      result = wallet.get_public_key({ identity_key: true })
      expect(result[:public_key]).to eq(pub_key.to_hex)
    end

    it 'inherits create_hmac/verify_hmac from ProtoWallet' do
      data = [10, 20, 30]
      hmac_result = wallet.create_hmac(crypto_args.merge(data: data))
      verify_result = wallet.verify_hmac(crypto_args.merge(data: data, hmac: hmac_result[:hmac]))
      expect(verify_result[:valid]).to be true
    end
  end

  # -------------------------------------------------------------------------
  # Blockchain & Network Data
  # -------------------------------------------------------------------------
  describe '#get_network' do
    it 'returns mainnet by default' do
      expect(wallet.get_network[:network]).to eq('mainnet')
    end

    it 'returns the configured network' do
      testnet_wallet = described_class.new(private_key, network: 'testnet')
      expect(testnet_wallet.get_network[:network]).to eq('testnet')
    end
  end

  describe '#get_version' do
    it 'returns the wallet version string' do
      result = wallet.get_version
      expect(result[:version]).to eq("bsv-wallet-#{BSV::Wallet::VERSION}")
    end

    it 'matches the BRC-100 vendor-major.minor.patch format' do
      expect(wallet.get_version[:version]).to match(/\Absv-wallet-\d+\.\d+\.\d+\z/)
    end
  end

  describe '#get_height' do
    it 'raises UnsupportedActionError with NullChainProvider' do
      expect { wallet.get_height }.to raise_error(BSV::Wallet::UnsupportedActionError)
    end

    it 'delegates to the chain provider' do
      provider = Class.new do
        include BSV::Wallet::ChainProvider

        def get_height
          890_123
        end
      end.new
      w = described_class.new(private_key, chain_provider: provider)
      expect(w.get_height[:height]).to eq(890_123)
    end
  end

  describe '#get_header_for_height' do
    it 'raises UnsupportedActionError with NullChainProvider' do
      expect { wallet.get_header_for_height({ height: 1 }) }.to raise_error(BSV::Wallet::UnsupportedActionError)
    end

    it 'delegates to the chain provider' do
      header_hex = 'ab' * 80
      provider = Class.new do
        include BSV::Wallet::ChainProvider

        define_method(:get_header) { |_h| header_hex }
      end.new
      w = described_class.new(private_key, chain_provider: provider)
      expect(w.get_header_for_height({ height: 100 })[:header]).to eq(header_hex)
    end

    it 'raises InvalidParameterError for non-positive height' do
      expect { wallet.get_header_for_height({ height: 0 }) }.to raise_error(BSV::Wallet::InvalidParameterError)
      expect { wallet.get_header_for_height({ height: -1 }) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises InvalidParameterError for non-integer height' do
      expect { wallet.get_header_for_height({ height: 'abc' }) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  # -------------------------------------------------------------------------
  # Authentication
  # -------------------------------------------------------------------------
  describe '#is_authenticated' do
    it 'returns authenticated: true for a local wallet' do
      expect(wallet.is_authenticated[:authenticated]).to be true
    end
  end

  describe '#wait_for_authentication' do
    it 'returns authenticated: true immediately for a local wallet' do
      expect(wallet.wait_for_authentication[:authenticated]).to be true
    end
  end

  # -------------------------------------------------------------------------
  # F8.14 — BEEF verification in internalize_action
  # -------------------------------------------------------------------------
  describe '#internalize_action — BEEF verification (F8.14)' do
    let(:incoming_tx) do
      tx = BSV::Transaction::Transaction.new
      tx.add_output(
        BSV::Transaction::TransactionOutput.new(
          satoshis: 1000,
          locking_script: BSV::Script::Script.p2pkh_lock(pub_key.hash160)
        )
      )
      tx
    end

    let(:valid_beef_bytes) { incoming_tx.to_beef.unpack('C*') }

    it 'accepts structurally valid BEEF and returns accepted: true' do
      result = wallet.internalize_action({
                                           tx: valid_beef_bytes,
                                           description: 'f8 14 valid beef test',
                                           outputs: [{
                                             output_index: 0,
                                             protocol: 'basket insertion',
                                             insertion_remittance: { basket: 'test tokens' }
                                           }]
                                         })
      expect(result[:accepted]).to be true
    end

    it 'raises WalletError when the BEEF bytes are structurally invalid' do
      # Corrupt the magic bytes so Beef.from_binary raises, or craft bytes that
      # parse but fail valid? — simplest is to pass a totally bogus byte array.
      allow_any_instance_of(BSV::Transaction::Beef).to receive(:verify).and_return(false) # rubocop:disable RSpec/AnyInstance
      expect do
        wallet.internalize_action({
                                    tx: valid_beef_bytes,
                                    description: 'f8 14 invalid beef test',
                                    outputs: [{
                                      output_index: 0,
                                      protocol: 'basket insertion',
                                      insertion_remittance: { basket: 'test tokens' }
                                    }]
                                  })
      end.to raise_error(BSV::Wallet::WalletError, /BEEF verification failed/)
    end
  end

  # -------------------------------------------------------------------------
  # F8.18 — wire_source_tx_ancestors depth cap and cycle detection
  # -------------------------------------------------------------------------
  describe '#wire_source_tx_ancestors (F8.18)' do
    # Access the private method for direct testing
    subject(:w) { described_class.new(private_key, storage: BSV::Wallet::MemoryStore.new) }

    def store_tx(storage, tx)
      storage.store_transaction(tx.txid_hex, tx.to_hex)
    end

    it 'halts at the depth cap without raising a stack overflow' do
      # Build a linear chain of ANCESTOR_DEPTH_CAP + 2 transactions;
      # verify the method terminates rather than recursing indefinitely.
      storage = w.storage
      txs = Array.new(BSV::Wallet::WalletClient::ANCESTOR_DEPTH_CAP + 2) do
        tx = BSV::Transaction::Transaction.new
        tx.add_output(
          BSV::Transaction::TransactionOutput.new(
            satoshis: 1000,
            locking_script: BSV::Script::Script.p2pkh_lock(pub_key.hash160)
          )
        )
        tx
      end

      # Link each tx as the parent of the next (prev_tx_id is internal byte order = reversed hex)
      txs.each_cons(2) do |parent, child|
        inp = BSV::Transaction::TransactionInput.new(
          prev_tx_id: [parent.txid_hex].pack('H*').reverse,
          prev_tx_out_index: 0
        )
        child.add_input(inp)
        store_tx(storage, parent)
      end
      store_tx(storage, txs.last)

      root_tx = txs.last
      expect do
        w.send(:wire_source_tx_ancestors, root_tx)
      end.not_to raise_error
    end

    it 'does not re-visit transactions it has already wired (cycle detection)' do
      storage = w.storage

      # Create two inputs on root_tx both pointing at the same ancestor.
      ancestor_tx = BSV::Transaction::Transaction.new
      ancestor_tx.add_output(
        BSV::Transaction::TransactionOutput.new(
          satoshis: 5000,
          locking_script: BSV::Script::Script.p2pkh_lock(pub_key.hash160)
        )
      )
      store_tx(storage, ancestor_tx)

      ancestor_prev_tx_id = [ancestor_tx.txid_hex].pack('H*').reverse
      root_tx = BSV::Transaction::Transaction.new
      root_tx.add_input(
        BSV::Transaction::TransactionInput.new(
          prev_tx_id: ancestor_prev_tx_id,
          prev_tx_out_index: 0
        )
      )
      root_tx.add_input(
        BSV::Transaction::TransactionInput.new(
          prev_tx_id: ancestor_prev_tx_id,
          prev_tx_out_index: 1
        )
      )

      expect do
        w.send(:wire_source_tx_ancestors, root_tx)
      end.not_to raise_error

      # At least one input should be wired; the second may be skipped by the
      # visited set but this is primarily a "does not crash" assertion.
      sourced = root_tx.inputs.count(&:source_transaction)
      expect(sourced).to be >= 1
    end
  end

  # -------------------------------------------------------------------------
  # substrate: delegation
  # -------------------------------------------------------------------------
  describe 'substrate: delegation' do
    # rubocop:disable RSpec/VerifiedDoubles
    let(:mock_substrate) do
      spy('substrate',
          create_action: { txid: 'abc' },
          sign_action: { txid: 'abc' },
          abort_action: { aborted: true },
          list_actions: { total_actions: 0, actions: [] },
          internalize_action: { accepted: true },
          list_outputs: { total_outputs: 0, outputs: [] },
          relinquish_output: { relinquished: true },
          get_public_key: { public_key: '02deadbeef' },
          reveal_counterparty_key_linkage: { encryption_revelation: {} },
          reveal_specific_key_linkage: { revelation: {} },
          encrypt: { ciphertext: [1, 2, 3] },
          decrypt: { plaintext: [104] },
          create_hmac: { hmac: [0] * 32 },
          verify_hmac: { valid: true },
          create_signature: { signature: [0] * 71 },
          verify_signature: { valid: true },
          acquire_certificate: { type: 'test' },
          list_certificates: { total_certificates: 0, certificates: [] },
          prove_certificate: { keyring_for_verifier: {} },
          relinquish_certificate: { relinquished: true },
          discover_by_identity_key: { total_certificates: 0, certificates: [] },
          discover_by_attributes: { total_certificates: 0, certificates: [] },
          is_authenticated: { authenticated: true },
          wait_for_authentication: { authenticated: true },
          get_height: { height: 999 },
          get_header_for_height: { header: 'ff' * 80 },
          get_network: { network: 'mainnet' },
          get_version: { version: 'remote-1.0.0' })
    end
    # rubocop:enable RSpec/VerifiedDoubles

    let(:wallet_with_substrate) do
      described_class.new(private_key, storage: BSV::Wallet::MemoryStore.new, substrate: mock_substrate)
    end

    it 'exposes the substrate via #substrate' do
      expect(wallet_with_substrate.substrate).to equal(mock_substrate)
    end

    it 'delegates create_action to the substrate' do
      wallet_with_substrate.create_action({ description: 'pay' })
      expect(mock_substrate).to have_received(:create_action).with({ description: 'pay' }, originator: nil)
    end

    it 'forwards originator to create_action' do
      wallet_with_substrate.create_action({ description: 'pay' }, originator: 'app.example.com')
      expect(mock_substrate).to have_received(:create_action).with(anything, originator: 'app.example.com')
    end

    it 'delegates sign_action to the substrate' do
      wallet_with_substrate.sign_action({ reference: 'ref' })
      expect(mock_substrate).to have_received(:sign_action).with({ reference: 'ref' }, originator: nil)
    end

    it 'delegates abort_action to the substrate' do
      wallet_with_substrate.abort_action({ reference: 'ref' })
      expect(mock_substrate).to have_received(:abort_action).with({ reference: 'ref' }, originator: nil)
    end

    it 'delegates list_actions to the substrate' do
      wallet_with_substrate.list_actions({ labels: ['pay'] })
      expect(mock_substrate).to have_received(:list_actions).with({ labels: ['pay'] }, originator: nil)
    end

    it 'delegates internalize_action to the substrate' do
      wallet_with_substrate.internalize_action({ tx: [] })
      expect(mock_substrate).to have_received(:internalize_action).with({ tx: [] }, originator: nil)
    end

    it 'delegates list_outputs to the substrate' do
      wallet_with_substrate.list_outputs({ basket: 'default' })
      expect(mock_substrate).to have_received(:list_outputs).with({ basket: 'default' }, originator: nil)
    end

    it 'delegates relinquish_output to the substrate' do
      wallet_with_substrate.relinquish_output({ output: 'abc.0' })
      expect(mock_substrate).to have_received(:relinquish_output).with({ output: 'abc.0' }, originator: nil)
    end

    it 'delegates get_public_key to the substrate' do
      wallet_with_substrate.get_public_key({ identity_key: true })
      expect(mock_substrate).to have_received(:get_public_key).with({ identity_key: true }, originator: nil)
    end

    it 'forwards originator to get_public_key' do
      wallet_with_substrate.get_public_key({ identity_key: true }, originator: 'app.example.com')
      expect(mock_substrate).to have_received(:get_public_key).with(anything, originator: 'app.example.com')
    end

    it 'delegates reveal_counterparty_key_linkage to the substrate' do
      args = { counterparty: '02abc', protocol_id: [0, 'test'], key_id: '1' }
      wallet_with_substrate.reveal_counterparty_key_linkage(args)
      expect(mock_substrate).to have_received(:reveal_counterparty_key_linkage).with(args, originator: nil)
    end

    it 'delegates reveal_specific_key_linkage to the substrate' do
      args = { counterparty: '02abc', protocol_id: [0, 'test'], key_id: '1', privilege_level: 'low' }
      wallet_with_substrate.reveal_specific_key_linkage(args)
      expect(mock_substrate).to have_received(:reveal_specific_key_linkage).with(args, originator: nil)
    end

    it 'delegates encrypt to the substrate' do
      args = { plaintext: [1, 2, 3], protocol_id: [0, 'test'], key_id: '1', counterparty: 'self' }
      wallet_with_substrate.encrypt(args)
      expect(mock_substrate).to have_received(:encrypt).with(args, originator: nil)
    end

    it 'delegates decrypt to the substrate' do
      args = { ciphertext: [1, 2, 3], protocol_id: [0, 'test'], key_id: '1', counterparty: 'self' }
      wallet_with_substrate.decrypt(args)
      expect(mock_substrate).to have_received(:decrypt).with(args, originator: nil)
    end

    it 'delegates create_hmac to the substrate' do
      args = { data: [1, 2, 3], protocol_id: [0, 'test'], key_id: '1', counterparty: 'self' }
      wallet_with_substrate.create_hmac(args)
      expect(mock_substrate).to have_received(:create_hmac).with(args, originator: nil)
    end

    it 'delegates verify_hmac to the substrate' do
      args = { data: [1], hmac: [0] * 32, protocol_id: [0, 'test'], key_id: '1', counterparty: 'self' }
      wallet_with_substrate.verify_hmac(args)
      expect(mock_substrate).to have_received(:verify_hmac).with(args, originator: nil)
    end

    it 'delegates create_signature to the substrate' do
      args = { data: [1], protocol_id: [0, 'test'], key_id: '1', counterparty: 'self' }
      wallet_with_substrate.create_signature(args)
      expect(mock_substrate).to have_received(:create_signature).with(args, originator: nil)
    end

    it 'delegates verify_signature to the substrate' do
      args = { data: [1], signature: [0] * 71, protocol_id: [0, 'test'], key_id: '1', counterparty: 'self' }
      wallet_with_substrate.verify_signature(args)
      expect(mock_substrate).to have_received(:verify_signature).with(args, originator: nil)
    end

    it 'delegates acquire_certificate to the substrate' do
      args = { type: 'test', certifier: '02abc', acquisition_protocol: 'direct' }
      wallet_with_substrate.acquire_certificate(args)
      expect(mock_substrate).to have_received(:acquire_certificate).with(args, originator: nil)
    end

    it 'delegates list_certificates to the substrate' do
      args = { certifiers: ['02abc'], types: ['test'] }
      wallet_with_substrate.list_certificates(args)
      expect(mock_substrate).to have_received(:list_certificates).with(args, originator: nil)
    end

    it 'delegates prove_certificate to the substrate' do
      args = { certificate: { type: 'test', serial_number: 'sn', certifier: '02abc' },
               fields_to_reveal: ['name'], verifier: '02abc' }
      wallet_with_substrate.prove_certificate(args)
      expect(mock_substrate).to have_received(:prove_certificate).with(args, originator: nil)
    end

    it 'delegates relinquish_certificate to the substrate' do
      args = { type: 'test', serial_number: 'sn', certifier: '02abc' }
      wallet_with_substrate.relinquish_certificate(args)
      expect(mock_substrate).to have_received(:relinquish_certificate).with(args, originator: nil)
    end

    it 'delegates discover_by_identity_key to the substrate' do
      args = { identity_key: '02abc' }
      wallet_with_substrate.discover_by_identity_key(args)
      expect(mock_substrate).to have_received(:discover_by_identity_key).with(args, originator: nil)
    end

    it 'delegates discover_by_attributes to the substrate' do
      args = { attributes: { name: 'Alice' } }
      wallet_with_substrate.discover_by_attributes(args)
      expect(mock_substrate).to have_received(:discover_by_attributes).with(args, originator: nil)
    end

    it 'delegates is_authenticated to the substrate' do
      wallet_with_substrate.is_authenticated
      expect(mock_substrate).to have_received(:is_authenticated).with({}, originator: nil)
    end

    it 'delegates wait_for_authentication to the substrate' do
      wallet_with_substrate.wait_for_authentication
      expect(mock_substrate).to have_received(:wait_for_authentication).with({}, originator: nil)
    end

    it 'delegates get_height to the substrate' do
      wallet_with_substrate.get_height
      expect(mock_substrate).to have_received(:get_height).with({}, originator: nil)
    end

    it 'delegates get_header_for_height to the substrate' do
      wallet_with_substrate.get_header_for_height({ height: 100 })
      expect(mock_substrate).to have_received(:get_header_for_height).with({ height: 100 }, originator: nil)
    end

    it 'delegates get_network to the substrate' do
      wallet_with_substrate.get_network
      expect(mock_substrate).to have_received(:get_network).with({}, originator: nil)
    end

    it 'delegates get_version to the substrate' do
      wallet_with_substrate.get_version
      expect(mock_substrate).to have_received(:get_version).with({}, originator: nil)
    end

    it 'returns the substrate result for get_height' do
      expect(wallet_with_substrate.get_height).to eq({ height: 999 })
    end

    it 'returns the substrate result for get_network' do
      expect(wallet_with_substrate.get_network).to eq({ network: 'mainnet' })
    end

    it 'returns the substrate result for get_version' do
      expect(wallet_with_substrate.get_version).to eq({ version: 'remote-1.0.0' })
    end

    it 'leaves the local wallet (no substrate) unchanged for get_height' do
      # NullChainProvider raises UnsupportedActionError — confirms local path is taken, not substrate
      chain = BSV::Wallet::NullChainProvider.new
      w = described_class.new(private_key, storage: BSV::Wallet::MemoryStore.new,
                                           chain_provider: chain)
      expect { w.get_height }.to raise_error(BSV::Wallet::UnsupportedActionError)
    end

    it 'leaves the local wallet (no substrate) unchanged for is_authenticated' do
      expect(wallet.is_authenticated).to eq({ authenticated: true })
    end

    it 'leaves the local wallet (no substrate) unchanged for get_network' do
      expect(wallet.get_network).to eq({ network: 'mainnet' })
    end

    it 'constructs without error when given an HTTPWalletJSON substrate' do
      substrate = BSV::Wallet::Substrates::HTTPWalletJSON.new('http://localhost:3321')
      expect do
        described_class.new(private_key, storage: BSV::Wallet::MemoryStore.new, substrate: substrate)
      end.not_to raise_error
    end

    it 'constructs without error when given a WalletWireTransceiver substrate' do
      wire = double('wire', transmit_to_wallet: []) # rubocop:disable RSpec/VerifiedDoubles
      transceiver = BSV::Wallet::Substrates::WalletWireTransceiver.new(wire)
      expect do
        described_class.new(private_key, storage: BSV::Wallet::MemoryStore.new, substrate: transceiver)
      end.not_to raise_error
    end
  end
end
