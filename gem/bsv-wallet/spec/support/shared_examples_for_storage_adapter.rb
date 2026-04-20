# frozen_string_literal: true

# Shared conformance specs for BSV::Wallet::Store implementations.
#
# Any class that includes +BSV::Wallet::Store+ should pass this
# suite. Callers provide a +store+ via +let(:store)+:
#
#   RSpec.describe BSV::Wallet::Store::Memory do
#     let(:store) { described_class.new }
#     it_behaves_like 'a storage adapter'
#   end
#
# The suite exercises the full interface: actions, outputs, certificates,
# proofs, transactions, count_*, and pagination.
RSpec.shared_examples 'a storage adapter' do
  it 'includes Store' do
    expect(store.class.ancestors).to include(BSV::Wallet::Store)
  end

  describe 'actions' do
    describe '#store_action' do
      it 'returns the stored action data' do
        data = { labels: ['payment'], txid: 'abc' }
        result = store.store_action(data)
        expect(result).to eq(data)
      end
    end

    describe '#find_actions' do
      it 'finds actions matching any of the given labels (default mode)' do
        store.store_action(labels: ['payment'], txid: 'abc')
        store.store_action(labels: ['transfer'], txid: 'def')

        results = store.find_actions(labels: ['payment'])
        expect(results.length).to eq(1)
        expect(results.first[:txid]).to eq('abc')
      end

      it 'finds actions matching any label when label_query_mode is "any"' do
        store.store_action(labels: %w[payment urgent], txid: 'abc')
        store.store_action(labels: ['urgent'], txid: 'def')

        results = store.find_actions(labels: ['payment'], label_query_mode: 'any')
        expect(results.length).to eq(1)
        expect(results.first[:txid]).to eq('abc')
      end

      it 'finds actions matching all given labels when label_query_mode is "all"' do
        store.store_action(labels: %w[payment urgent], txid: 'abc')
        store.store_action(labels: ['payment'], txid: 'def')

        results = store.find_actions(labels: %w[payment urgent], label_query_mode: 'all')
        expect(results.length).to eq(1)
        expect(results.first[:txid]).to eq('abc')
      end

      it 'returns an empty array when no actions match' do
        store.store_action(labels: ['payment'], txid: 'abc')
        expect(store.find_actions(labels: ['transfer'])).to be_empty
      end

      it 'returns all actions when no label filter is given' do
        store.store_action(labels: ['a'], txid: 'tx1')
        store.store_action(labels: ['b'], txid: 'tx2')
        results = store.find_actions({})
        expect(results.length).to eq(2)
      end
    end

    describe '#update_action_status' do
      before do
        store.store_action(labels: ['payment'], txid: 'abc', status: 'completed')
      end

      it 'updates the status of the matching action' do
        store.update_action_status('abc', 'failed')
        results = store.find_actions({})
        expect(results.first[:status].to_s).to eq('failed')
      end

      it 'returns the updated action hash' do
        result = store.update_action_status('abc', 'failed')
        expect(result).to be_a(Hash)
        expect(result[:txid]).to eq('abc')
      end

      it 'raises WalletError when no action with the given txid exists' do
        expect do
          store.update_action_status('nonexistent', 'failed')
        end.to raise_error(BSV::Wallet::WalletError, /nonexistent/)
      end
    end

    describe '#delete_action' do
      before do
        store.store_action(labels: ['payment'], txid: 'abc')
      end

      it 'removes the action and returns true' do
        expect(store.delete_action('abc')).to be true
        expect(store.find_actions({})).to be_empty
      end

      it 'returns false when no action with the given txid exists' do
        expect(store.delete_action('nonexistent')).to be false
      end

      it 'does not affect other actions' do
        store.store_action(labels: ['transfer'], txid: 'def')
        store.delete_action('abc')
        results = store.find_actions({})
        expect(results.length).to eq(1)
        expect(results.first[:txid]).to eq('def')
      end
    end
  end

  describe 'outputs' do
    describe '#store_output' do
      it 'returns the stored output data' do
        data = { basket: 'my tokens', outpoint: 'abc.0', spendable: true }
        result = store.store_output(data)
        expect(result).to eq(data)
      end
    end

    describe '#find_outputs' do
      it 'finds outputs by basket name' do
        store.store_output(basket: 'my tokens', outpoint: 'abc.0', spendable: true)
        store.store_output(basket: 'other tokens', outpoint: 'def.0', spendable: true)

        results = store.find_outputs(basket: 'my tokens')
        expect(results.length).to eq(1)
        expect(results.first[:outpoint]).to eq('abc.0')
      end

      it 'finds outputs by outpoint' do
        store.store_output(basket: 'my tokens', outpoint: 'abc.0', spendable: true)
        store.store_output(basket: 'my tokens', outpoint: 'def.0', spendable: true)

        results = store.find_outputs(outpoint: 'abc.0')
        expect(results.length).to eq(1)
        expect(results.first[:outpoint]).to eq('abc.0')
      end

      it 'excludes spent outputs by default' do
        store.store_output(basket: 'my tokens', outpoint: 'abc.0', spendable: true)
        store.store_output(basket: 'my tokens', outpoint: 'def.0', spendable: false)

        results = store.find_outputs(basket: 'my tokens')
        expect(results.length).to eq(1)
        expect(results.first[:outpoint]).to eq('abc.0')
      end

      it 'includes spent outputs when include_spent is true' do
        store.store_output(basket: 'my tokens', outpoint: 'abc.0', spendable: true)
        store.store_output(basket: 'my tokens', outpoint: 'def.0', spendable: false)

        results = store.find_outputs(basket: 'my tokens', include_spent: true)
        expect(results.length).to eq(2)
      end

      it 'filters by tags in "any" mode' do
        store.store_output(basket: 'my tokens', outpoint: 'abc.0', spendable: true, tags: %w[rare gold])
        store.store_output(basket: 'my tokens', outpoint: 'def.0', spendable: true, tags: ['common'])

        results = store.find_outputs(basket: 'my tokens', tags: ['rare'])
        expect(results.length).to eq(1)
        expect(results.first[:outpoint]).to eq('abc.0')
      end

      it 'filters by tags in "all" mode' do
        store.store_output(basket: 'my tokens', outpoint: 'abc.0', spendable: true, tags: %w[rare gold])
        store.store_output(basket: 'my tokens', outpoint: 'def.0', spendable: true, tags: ['rare'])

        results = store.find_outputs(basket: 'my tokens', tags: %w[rare gold], tag_query_mode: 'all')
        expect(results.length).to eq(1)
        expect(results.first[:outpoint]).to eq('abc.0')
      end
    end

    describe '#delete_output' do
      it 'removes the output and returns true' do
        store.store_output(basket: 'my tokens', outpoint: 'abc.0', spendable: true)
        expect(store.delete_output('abc.0')).to be true
        expect(store.find_outputs(basket: 'my tokens', include_spent: true)).to be_empty
      end

      it 'returns false when the outpoint does not exist' do
        expect(store.delete_output('nonexistent.0')).to be false
      end
    end

    # Regression: symbol values stored in output hashes become strings after
    # JSON round-tripping (PostgresStore, FileStore). Code that compares
    # with == :symbol silently fails. See #367.
    describe 'symbol/string round-trip safety' do
      it 'preserves derivation_type for .to_s comparison after round-trip' do
        store.store_output(
          basket: 'default', outpoint: 'sym.0', spendable: true,
          satoshis: 1000, derivation_type: :identity
        )
        output = store.find_outputs(basket: 'default', outpoint: 'sym.0', include_spent: true).first
        expect(output[:derivation_type].to_s).to eq('identity')
      end

      it 'preserves state for .to_s comparison after round-trip' do
        store.store_output(
          basket: 'default', outpoint: 'state.0', spendable: true,
          satoshis: 500, state: :spendable
        )
        output = store.find_outputs(basket: 'default', outpoint: 'state.0', include_spent: true).first
        expect(output[:state].to_s).to eq('spendable')
      end

      it 'round-tripped symbol values work with the .to_s == pattern' do
        store.store_output(
          basket: 'default', outpoint: 'pat.0', spendable: true,
          satoshis: 750, derivation_type: :identity, custom_enum: :foo
        )
        output = store.find_outputs(basket: 'default', outpoint: 'pat.0', include_spent: true).first

        # This is how code SHOULD compare — survives both MemoryStore and PostgresStore
        expect(output[:derivation_type]&.to_s == 'identity').to be true
        expect(output[:custom_enum]&.to_s == 'foo').to be true

        # This is the anti-pattern — works in MemoryStore, fails in PostgresStore
        # We don't assert it fails (MemoryStore would pass), but we document
        # that .to_s is the correct approach.
      end
    end
  end

  describe 'certificates' do
    describe '#store_certificate' do
      it 'returns the stored certificate data' do
        data = { type: 'cert1', certifier: 'abc', serial_number: 's1' }
        result = store.store_certificate(data)
        expect(result).to eq(data)
      end
    end

    describe '#find_certificates' do
      it 'finds certificates by certifier' do
        store.store_certificate(type: 'cert1', certifier: 'abc', serial_number: 's1')
        store.store_certificate(type: 'cert1', certifier: 'def', serial_number: 's2')

        results = store.find_certificates(certifiers: ['abc'])
        expect(results.length).to eq(1)
        expect(results.first[:serial_number]).to eq('s1')
      end

      it 'finds certificates by type' do
        store.store_certificate(type: 'id', certifier: 'abc', serial_number: 's1')
        store.store_certificate(type: 'age', certifier: 'abc', serial_number: 's2')

        results = store.find_certificates(types: ['id'])
        expect(results.length).to eq(1)
        expect(results.first[:type]).to eq('id')
      end

      it 'combines certifier and type filters' do
        store.store_certificate(type: 'id', certifier: 'abc', serial_number: 's1')
        store.store_certificate(type: 'age', certifier: 'abc', serial_number: 's2')
        store.store_certificate(type: 'id', certifier: 'def', serial_number: 's3')

        results = store.find_certificates(certifiers: ['abc'], types: ['id'])
        expect(results.length).to eq(1)
        expect(results.first[:serial_number]).to eq('s1')
      end

      it 'filters by subject' do
        store.store_certificate(type: 'id', certifier: 'abc', serial_number: 's1', subject: 'alice')
        store.store_certificate(type: 'id', certifier: 'abc', serial_number: 's2', subject: 'bob')

        results = store.find_certificates(subject: 'alice')
        expect(results.length).to eq(1)
        expect(results.first[:serial_number]).to eq('s1')
      end

      it 'filters by attributes matching certificate fields' do
        store.store_certificate(type: 'id', certifier: 'abc', serial_number: 's1',
                                fields: { name: 'alice', age: '30' })
        store.store_certificate(type: 'id', certifier: 'abc', serial_number: 's2',
                                fields: { name: 'bob', age: '30' })

        results = store.find_certificates(attributes: { name: 'alice' })
        expect(results.length).to eq(1)
        expect(results.first[:serial_number]).to eq('s1')
      end

      it 'returns all certificates when no filters are given' do
        store.store_certificate(type: 'id', certifier: 'abc', serial_number: 's1')
        store.store_certificate(type: 'age', certifier: 'def', serial_number: 's2')
        expect(store.find_certificates({}).length).to eq(2)
      end
    end

    describe '#delete_certificate' do
      it 'removes the certificate and returns true' do
        store.store_certificate(type: 'cert1', certifier: 'abc', serial_number: 's1')
        expect(store.delete_certificate(type: 'cert1', serial_number: 's1', certifier: 'abc')).to be true
        expect(store.find_certificates(certifiers: ['abc'])).to be_empty
      end

      it 'returns false when the certificate does not exist' do
        expect(store.delete_certificate(type: 'x', serial_number: 'y', certifier: 'z')).to be false
      end

      it 'requires all three keys to match for deletion' do
        store.store_certificate(type: 'cert1', certifier: 'abc', serial_number: 's1')
        expect(store.delete_certificate(type: 'cert1', serial_number: 'wrong', certifier: 'abc')).to be false
        expect(store.find_certificates(certifiers: ['abc']).length).to eq(1)
      end
    end
  end

  describe 'proofs' do
    let(:txid) { 'a' * 64 }
    let(:bump_hex) { 'fe6e6d0c000e02fd8e0602' }

    it 'round-trips a proof via store_proof/find_proof' do
      store.store_proof(txid, bump_hex)
      expect(store.find_proof(txid)).to eq(bump_hex)
    end

    it 'returns nil for an unknown txid' do
      expect(store.find_proof('nonexistent')).to be_nil
    end

    it 'overwrites an existing proof on re-store' do
      store.store_proof(txid, bump_hex)
      store.store_proof(txid, 'fe00000000')
      expect(store.find_proof(txid)).to eq('fe00000000')
    end
  end

  describe 'transactions' do
    let(:txid) { 'b' * 64 }
    let(:tx_hex) { '0100000001abcd' }

    it 'round-trips a transaction via store_transaction/find_transaction' do
      store.store_transaction(txid, tx_hex)
      expect(store.find_transaction(txid)).to eq(tx_hex)
    end

    it 'returns nil for an unknown txid' do
      expect(store.find_transaction('nonexistent')).to be_nil
    end

    it 'overwrites an existing transaction on re-store' do
      store.store_transaction(txid, tx_hex)
      store.store_transaction(txid, '0200000000')
      expect(store.find_transaction(txid)).to eq('0200000000')
    end
  end

  describe '#count_actions' do
    before do
      store.store_action(labels: %w[payment urgent], txid: 'abc')
      store.store_action(labels: ['payment'], txid: 'def')
      store.store_action(labels: ['transfer'], txid: 'ghi')
    end

    it 'counts all actions when no label filter is given' do
      expect(store.count_actions({})).to eq(3)
    end

    it 'counts actions matching any of the given labels' do
      expect(store.count_actions(labels: ['payment'])).to eq(2)
    end

    it 'counts actions matching all given labels' do
      expect(store.count_actions(labels: %w[payment urgent], label_query_mode: 'all')).to eq(1)
    end

    it 'returns 0 when no actions match the filter' do
      expect(store.count_actions(labels: ['nonexistent'])).to eq(0)
    end

    it 'counts the full set without applying pagination' do
      10.times { |i| store.store_action(labels: ['bulk'], txid: "bulk#{i}") }
      expect(store.count_actions(labels: ['bulk'])).to eq(10)
    end
  end

  describe '#count_outputs' do
    before do
      store.store_output(basket: 'my tokens', outpoint: 'abc.0', spendable: true, tags: %w[rare gold])
      store.store_output(basket: 'my tokens', outpoint: 'def.0', spendable: true, tags: ['rare'])
      store.store_output(basket: 'other basket', outpoint: 'ghi.0', spendable: true)
    end

    it 'counts all spendable outputs in the specified basket' do
      expect(store.count_outputs(basket: 'my tokens')).to eq(2)
    end

    it 'counts outputs in a different basket' do
      expect(store.count_outputs(basket: 'other basket')).to eq(1)
    end

    it 'returns 0 for an empty basket' do
      expect(store.count_outputs(basket: 'empty basket')).to eq(0)
    end

    it 'counts outputs filtered by tag in "any" mode' do
      expect(store.count_outputs(basket: 'my tokens', tags: ['gold'])).to eq(1)
    end

    it 'counts outputs filtered by all tags' do
      expect(store.count_outputs(basket: 'my tokens', tags: %w[rare gold], tag_query_mode: 'all')).to eq(1)
    end

    it 'excludes spent outputs by default' do
      store.store_output(basket: 'my tokens', outpoint: 'spent.0', spendable: false)
      expect(store.count_outputs(basket: 'my tokens')).to eq(2)
    end

    it 'counts spent outputs when include_spent is true' do
      store.store_output(basket: 'my tokens', outpoint: 'spent.0', spendable: false)
      expect(store.count_outputs(basket: 'my tokens', include_spent: true)).to eq(3)
    end

    it 'counts the full set without applying pagination' do
      15.times { |i| store.store_output(basket: 'bulk basket', outpoint: "bulk#{i}.0", spendable: true) }
      expect(store.count_outputs(basket: 'bulk basket')).to eq(15)
    end
  end

  describe '#count_certificates' do
    before do
      store.store_certificate(type: 'id',  certifier: 'abc', serial_number: 's1')
      store.store_certificate(type: 'id',  certifier: 'def', serial_number: 's2')
      store.store_certificate(type: 'age', certifier: 'abc', serial_number: 's3')
    end

    it 'counts all certificates when no filter is given' do
      expect(store.count_certificates({})).to eq(3)
    end

    it 'counts certificates matching a certifier filter' do
      expect(store.count_certificates(certifiers: ['abc'])).to eq(2)
    end

    it 'counts certificates matching a type filter' do
      expect(store.count_certificates(types: ['id'])).to eq(2)
    end

    it 'counts the full set without applying pagination' do
      15.times { |i| store.store_certificate(type: 'bulk', certifier: 'c', serial_number: "s#{i}") }
      expect(store.count_certificates(types: ['bulk'])).to eq(15)
    end
  end

  describe 'pagination' do
    before do
      5.times { |i| store.store_action(labels: ['all'], txid: "tx#{i}") }
    end

    it 'limits results to the given limit' do
      results = store.find_actions(labels: ['all'], limit: 2)
      expect(results.length).to eq(2)
    end

    it 'skips results by offset and returns records in insertion order' do
      results = store.find_actions(labels: ['all'], limit: 2, offset: 1)
      expect(results.length).to eq(2)
      expect(results.first[:txid]).to eq('tx1')
      expect(results.last[:txid]).to eq('tx2')
    end

    it 'applies a default limit of 10' do
      15.times { |i| store.store_action(labels: ['many'], txid: "extra#{i}") }
      results = store.find_actions(labels: ['many'])
      expect(results.length).to eq(10)
    end

    it 'returns an empty array when offset exceeds total results' do
      results = store.find_actions(labels: ['all'], offset: 100)
      expect(results).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # Auto-fund interface contract
  # These four methods form the UTXO state-management contract.  All adapter
  # implementations must pass this suite unchanged.  State values may be
  # returned as Symbols or Strings depending on serialisation (MemoryStore
  # uses Symbols; FileStore and PostgresStore use Strings after a round-trip).
  # Examples use `.to_s` to normalise before comparing.
  # ---------------------------------------------------------------------------

  describe 'auto-fund interface' do
    describe '#find_spendable_outputs' do
      before do
        store.store_output(basket: 'default', outpoint: 'aa.0', spendable: true, satoshis: 500,
                           state: :spendable)
        store.store_output(basket: 'default', outpoint: 'bb.0', spendable: true, satoshis: 1000,
                           state: :spendable)
        store.store_output(basket: 'default', outpoint: 'cc.0', spendable: true, satoshis: 200,
                           state: :spendable)
        store.store_output(basket: 'other',   outpoint: 'dd.0', spendable: true, satoshis: 800,
                           state: :spendable)
        store.store_output(basket: 'default', outpoint: 'ee.0', spendable: false, satoshis: 300,
                           state: :spent)
      end

      it 'returns outputs sorted largest-first by default' do
        results = store.find_spendable_outputs(basket: 'default')
        expect(results.map { |o| o[:satoshis] }).to eq([1000, 500, 200])
      end

      it 'returns outputs sorted smallest-first when sort_order is :asc' do
        results = store.find_spendable_outputs(basket: 'default', sort_order: :asc)
        expect(results.map { |o| o[:satoshis] }).to eq([200, 500, 1000])
      end

      it 'filters by basket' do
        results = store.find_spendable_outputs(basket: 'default')
        expect(results.map { |o| o[:outpoint] }).not_to include('dd.0')
      end

      it 'returns outputs from all baskets when no basket filter is given' do
        results = store.find_spendable_outputs
        expect(results.map { |o| o[:outpoint] }).to include('aa.0', 'dd.0')
      end

      it 'filters by min_satoshis' do
        results = store.find_spendable_outputs(basket: 'default', min_satoshis: 500)
        expect(results.map { |o| o[:outpoint] }).to contain_exactly('aa.0', 'bb.0')
      end

      it 'excludes non-spendable outputs' do
        results = store.find_spendable_outputs(basket: 'default')
        expect(results.map { |o| o[:outpoint] }).not_to include('ee.0')
      end

      it 'returns an empty array when the basket is empty' do
        expect(store.find_spendable_outputs(basket: 'nonexistent')).to be_empty
      end

      it 'treats a legacy output with spendable: true and no state as spendable' do
        store.store_output(basket: 'legacy', outpoint: 'leg.0', satoshis: 999, spendable: true)
        results = store.find_spendable_outputs(basket: 'legacy')
        expect(results.map { |o| o[:outpoint] }).to include('leg.0')
      end
    end

    describe '#update_output_state' do
      before do
        store.store_output(basket: 'default', outpoint: 'tx.0', spendable: true, satoshis: 1000,
                           state: :spendable)
      end

      it 'transitions to :pending and records pending metadata' do
        store.update_output_state('tx.0', :pending, pending_reference: 'ref-001', no_send: false)
        results = store.find_outputs(outpoint: 'tx.0', include_spent: true, limit: 1, offset: 0)
        row = results.first
        expect(row[:state].to_s).to eq('pending')
        expect(row[:pending_reference]).to eq('ref-001')
        expect(row[:pending_since]).not_to be_nil
      end

      it 'transitions to :spent' do
        store.update_output_state('tx.0', :spent)
        results = store.find_outputs(outpoint: 'tx.0', include_spent: true, limit: 1, offset: 0)
        expect(results.first[:state].to_s).to eq('spent')
      end

      it 'transitions back to :spendable and clears pending metadata' do
        store.update_output_state('tx.0', :pending, pending_reference: 'ref-x', no_send: false)
        store.update_output_state('tx.0', :spendable)
        results = store.find_outputs(outpoint: 'tx.0', include_spent: true, limit: 1, offset: 0)
        row = results.first
        expect(row[:state].to_s).to eq('spendable')
        expect(row[:pending_since]).to be_nil
        expect(row[:pending_reference]).to be_nil
      end

      it 'returns the updated output hash' do
        result = store.update_output_state('tx.0', :spent)
        expect(result).to be_a(Hash)
        expect(result[:outpoint]).to eq('tx.0')
      end

      it 'raises WalletError when the outpoint does not exist' do
        expect do
          store.update_output_state('nonexistent.0', :spent)
        end.to raise_error(BSV::Wallet::WalletError, /nonexistent\.0/)
      end

      it 'sets no_send: true when passed' do
        store.update_output_state('tx.0', :pending, pending_reference: 'ref-ns', no_send: true)
        result = store.update_output_state('tx.0', :spendable)
        # After clearing, no_send must be absent or falsy
        expect(result[:no_send]).to be_falsy
      end
    end

    describe '#lock_utxos' do
      before do
        store.store_output(basket: 'default', outpoint: 'tx1.0', spendable: true, satoshis: 500,
                           state: :spendable)
        store.store_output(basket: 'default', outpoint: 'tx2.0', spendable: true, satoshis: 1000,
                           state: :spendable)
        store.store_output(basket: 'default', outpoint: 'tx3.0', spendable: false, satoshis: 200,
                           state: :spent)
      end

      it 'locks spendable outputs and returns the locked outpoints' do
        locked = store.lock_utxos(%w[tx1.0 tx2.0], reference: 'ref-abc', no_send: false)
        expect(locked).to contain_exactly('tx1.0', 'tx2.0')
      end

      it 'returns an empty array when given an empty list' do
        expect(store.lock_utxos([], reference: 'ref')).to eq([])
      end

      it 'skips outputs that are not in spendable state' do
        locked = store.lock_utxos(%w[tx1.0 tx3.0], reference: 'ref', no_send: false)
        expect(locked).to contain_exactly('tx1.0')
      end

      it 'skips outputs already locked (pending)' do
        store.update_output_state('tx1.0', :pending, pending_reference: 'first', no_send: false)
        locked = store.lock_utxos(['tx1.0'], reference: 'second', no_send: false)
        expect(locked).to be_empty
      end

      it 'marks locked outputs as pending so they disappear from find_spendable_outputs' do
        store.lock_utxos(['tx1.0'], reference: 'ref-001', no_send: false)
        results = store.find_spendable_outputs(basket: 'default')
        expect(results.map { |o| o[:outpoint] }).not_to include('tx1.0')
      end

      it 'sets no_send flag on the locked output when passed' do
        store.lock_utxos(['tx1.0'], reference: 'ref-ns', no_send: true)
        results = store.find_outputs(outpoint: 'tx1.0', include_spent: true, limit: 1, offset: 0)
        expect(results.first[:no_send]).to be true
      end
    end

    describe '#release_stale_pending!' do
      before do
        store.store_output(basket: 'default', outpoint: 'tx1.0', spendable: true, satoshis: 500,
                           state: :spendable)
        store.store_output(basket: 'default', outpoint: 'tx2.0', spendable: true, satoshis: 500,
                           state: :spendable)
        store.store_output(basket: 'default', outpoint: 'tx3.0', spendable: true, satoshis: 500,
                           state: :spendable)
      end

      it 'returns 0 when no pending outputs exist' do
        expect(store.release_stale_pending!(timeout: 300)).to eq(0)
      end

      it 'returns 0 when pending outputs are within the timeout window' do
        store.lock_utxos(['tx1.0'], reference: 'fresh', no_send: false)
        expect(store.release_stale_pending!(timeout: 300)).to eq(0)
      end

      it 'releases a pending output that is past the timeout and returns count' do
        # timeout: 0 makes any lock immediately stale (cutoff = now, locked_at < now is true)
        store.lock_utxos(['tx1.0'], reference: 'stale', no_send: false)
        released = store.release_stale_pending!(timeout: 0)
        expect(released).to eq(1)
      end

      it 'restores state to spendable after releasing a stale lock' do
        store.lock_utxos(['tx2.0'], reference: 'stale', no_send: false)
        store.release_stale_pending!(timeout: 0)

        results = store.find_spendable_outputs(basket: 'default')
        expect(results.map { |o| o[:outpoint] }).to include('tx2.0')
      end

      it 'does not release no_send pending outputs even when stale' do
        # timeout: 0 means cutoff = now; any pending lock is already "stale"
        # but no_send: true must exempt it from automatic release
        store.lock_utxos(['tx3.0'], reference: 'ns', no_send: true)
        expect(store.release_stale_pending!(timeout: 0)).to eq(0)

        results = store.find_spendable_outputs(basket: 'default')
        expect(results.map { |o| o[:outpoint] }).not_to include('tx3.0')
      end
    end
  end

  describe '#update_output_basket' do
    let(:outpoint) { 'basket.0' }

    before do
      store.store_output(
        outpoint: outpoint,
        satoshis: 5_000,
        basket: 'old basket',
        state: :spendable,
        tags: %w[rare gold],
        derivation_prefix: 'prefix123',
        derivation_suffix: 'suffix456',
        sender_identity_key: "02#{'ab' * 32}"
      )
    end

    it 'changes the basket of an existing output' do
      store.update_output_basket(outpoint, 'pool:doom')
      results = store.find_outputs(basket: 'pool:doom', include_spent: true, limit: 1, offset: 0)
      expect(results.length).to eq(1)
      expect(results.first[:outpoint]).to eq(outpoint)
    end

    it 'returns the updated output hash' do
      result = store.update_output_basket(outpoint, 'pool:doom')
      expect(result).to be_a(Hash)
      expect(result[:outpoint]).to eq(outpoint)
      expect(result[:basket]).to eq('pool:doom')
    end

    it 'raises WalletError when outpoint not found' do
      expect do
        store.update_output_basket('nonexistent.99', 'pool:doom')
      end.to raise_error(BSV::Wallet::WalletError)
    end

    it 'preserves satoshis, state, tags, and derivation fields' do
      result = store.update_output_basket(outpoint, 'pool:doom')
      expect(result[:satoshis]).to eq(5_000)
      expect(result[:state].to_s).to eq('spendable')
      expect(result[:tags]).to include('rare', 'gold')
      expect(result[:derivation_prefix]).to eq('prefix123')
      expect(result[:derivation_suffix]).to eq('suffix456')
    end

    it 'leaves a pending output still pending (basket change is metadata-only)' do
      store.update_output_state(outpoint, :pending, pending_reference: 'ref-x')
      result = store.update_output_basket(outpoint, 'pool:doom')
      expect(result[:state].to_s).to eq('pending')
    end

    it 'output appears in new basket via find_spendable_outputs' do
      store.update_output_basket(outpoint, 'pool:doom')
      results = store.find_spendable_outputs(basket: 'pool:doom')
      expect(results.map { |o| o[:outpoint] }).to include(outpoint)
    end

    it 'output disappears from old basket via find_spendable_outputs' do
      store.update_output_basket(outpoint, 'pool:doom')
      results = store.find_spendable_outputs(basket: 'old basket')
      expect(results.map { |o| o[:outpoint] }).not_to include(outpoint)
    end
  end

  describe 'settings' do
    describe '#store_setting and #find_setting' do
      it 'persists a setting and retrieves it by key' do
        store.store_setting('change_params', '{"count":3}')
        expect(store.find_setting('change_params')).to eq('{"count":3}')
      end

      it 'returns nil for an unknown key' do
        expect(store.find_setting('nonexistent')).to be_nil
      end

      it 'overwrites an existing setting on re-store' do
        store.store_setting('change_params', '{"count":1}')
        store.store_setting('change_params', '{"count":5}')
        expect(store.find_setting('change_params')).to eq('{"count":5}')
      end

      it 'stores multiple independent settings without interference' do
        store.store_setting('change_params', '{"count":3}')
        store.store_setting('other_setting', 'hello')
        expect(store.find_setting('change_params')).to eq('{"count":3}')
        expect(store.find_setting('other_setting')).to eq('hello')
      end
    end
  end
end
