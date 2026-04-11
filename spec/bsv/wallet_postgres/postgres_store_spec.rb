# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet-postgres'

RSpec.describe BSV::Wallet::PostgresStore, :postgres do
  let(:db) { POSTGRES_TEST_DB }
  let(:store) { described_class.new(db) }

  before do
    POSTGRES_WALLET_TABLES.each { |t| db[t].truncate }
  end

  # The full StorageAdapter contract — same suite MemoryStore and
  # FileStore drive. Running it here guarantees PostgresStore never
  # drifts from the interface.
  it_behaves_like 'a storage adapter'

  describe 'postgres-specific behaviour' do
    describe 'output upsert semantics' do
      it 'last-write-wins on outpoint (no duplicate rows)' do
        store.store_output(basket: 'b', outpoint: 'abc.0', spendable: true, tags: ['old'])
        store.store_output(basket: 'b', outpoint: 'abc.0', spendable: false, tags: ['new'])

        expect(db[:wallet_outputs].where(outpoint: 'abc.0').count).to eq(1)
        result = store.find_outputs(outpoint: 'abc.0', include_spent: true).first
        expect(result[:tags]).to eq(['new'])
        expect(result[:spendable]).to be false
      end
    end

    describe 'certificate upsert semantics' do
      it 'last-write-wins on composite (type, serial_number, certifier)' do
        store.store_certificate(type: 'id', serial_number: 's1', certifier: 'c', subject: 'alice')
        store.store_certificate(type: 'id', serial_number: 's1', certifier: 'c', subject: 'bob')

        expect(db[:wallet_certificates].count).to eq(1)
        expect(store.find_certificates({}).first[:subject]).to eq('bob')
      end

      it 'treats different certifiers as distinct certificates' do
        store.store_certificate(type: 'id', serial_number: 's1', certifier: 'c1')
        store.store_certificate(type: 'id', serial_number: 's1', certifier: 'c2')

        expect(db[:wallet_certificates].count).to eq(2)
      end
    end

    describe 'tag GIN semantics' do
      before do
        store.store_output(basket: 'b', outpoint: 'a.0', spendable: true, tags: %w[rare gold shiny])
        store.store_output(basket: 'b', outpoint: 'b.0', spendable: true, tags: %w[rare silver])
        store.store_output(basket: 'b', outpoint: 'c.0', spendable: true, tags: %w[common])
      end

      it 'overlaps operator (any) matches outputs sharing at least one tag' do
        results = store.find_outputs(basket: 'b', tags: %w[shiny silver])
        expect(results.map { |o| o[:outpoint] }).to contain_exactly('a.0', 'b.0')
      end

      it 'contains operator (all) matches outputs carrying every tag' do
        results = store.find_outputs(basket: 'b', tags: %w[rare gold], tag_query_mode: 'all')
        expect(results.map { |o| o[:outpoint] }).to contain_exactly('a.0')
      end
    end

    describe 'jsonb attributes filter' do
      it 'matches nested field hashes via containment' do
        store.store_certificate(type: 'id', certifier: 'c', serial_number: 's1',
                                fields: { name: 'alice', age: '30', country: 'UK' })
        store.store_certificate(type: 'id', certifier: 'c', serial_number: 's2',
                                fields: { name: 'alice', age: '40', country: 'US' })
        store.store_certificate(type: 'id', certifier: 'c', serial_number: 's3',
                                fields: { name: 'bob' })

        results = store.find_certificates(attributes: { name: 'alice', age: '30' })
        expect(results.length).to eq(1)
        expect(results.first[:serial_number]).to eq('s1')
      end

      it 'returns an empty result when no certificate matches all attributes' do
        store.store_certificate(type: 'id', certifier: 'c', serial_number: 's1',
                                fields: { name: 'alice' })

        expect(store.find_certificates(attributes: { name: 'alice', age: '99' })).to be_empty
      end
    end

    describe 'concurrent output upsert' do
      it 'ends with a single row regardless of insert order' do
        threads = Array.new(5) do |i|
          Thread.new do
            store.store_output(basket: 'race', outpoint: 'race.0', spendable: true, tags: ["t#{i}"])
          end
        end
        threads.each(&:join)

        expect(db[:wallet_outputs].where(outpoint: 'race.0').count).to eq(1)
      end
    end

    describe 'jsonb round-trip fidelity' do
      it 'preserves deeply nested hashes, arrays, and unicode on read' do
        stored = {
          basket: 'round-trip',
          outpoint: 'abc.0',
          spendable: true,
          tags: %w[rare gold],
          satoshis: 1000,
          description: 'test — with unicode ✓ и 日本語',
          nested: {
            deeply: {
              keyed: {
                values: [1, 2, { inner: 'x', mixed: [true, nil, 3.14] }]
              }
            }
          }
        }

        store.store_output(stored)
        found = store.find_outputs(outpoint: 'abc.0').first

        expect(found).to eq(stored)
      end
    end

    describe '#find_spendable_outputs' do
      before do
        store.store_output(basket: 'default', outpoint: 'aa.0', spendable: true, satoshis: 500)
        store.store_output(basket: 'default', outpoint: 'bb.0', spendable: true, satoshis: 1000)
        store.store_output(basket: 'default', outpoint: 'cc.0', spendable: true, satoshis: 200)
        store.store_output(basket: 'other',   outpoint: 'dd.0', spendable: true, satoshis: 800)
        store.store_output(basket: 'default', outpoint: 'ee.0', spendable: false, satoshis: 300)
      end

      it 'returns only spendable outputs' do
        results = store.find_spendable_outputs
        outpoints = results.map { |o| o[:outpoint] }
        expect(outpoints).not_to include('ee.0')
      end

      it 'includes legacy rows with state NULL and spendable true' do
        # All rows stored via store_output have state populated; simulate legacy row
        db[:wallet_outputs]
          .where(outpoint: 'aa.0')
          .update(state: nil, spendable: true)

        results = store.find_spendable_outputs(basket: 'default')
        expect(results.map { |o| o[:outpoint] }).to include('aa.0')
      end

      it 'filters by basket when provided' do
        results = store.find_spendable_outputs(basket: 'default')
        outpoints = results.map { |o| o[:outpoint] }
        expect(outpoints).not_to include('dd.0')
        expect(outpoints).to include('aa.0', 'bb.0', 'cc.0')
      end

      it 'orders largest-first by default (desc)' do
        results = store.find_spendable_outputs(basket: 'default')
        satoshis = results.map { |o| o[:satoshis] }
        expect(satoshis).to eq(satoshis.sort.reverse)
      end

      it 'orders smallest-first when sort_order is :asc' do
        results = store.find_spendable_outputs(basket: 'default', sort_order: :asc)
        satoshis = results.map { |o| o[:satoshis] }
        expect(satoshis).to eq(satoshis.sort)
      end

      it 'filters by min_satoshis' do
        results = store.find_spendable_outputs(basket: 'default', min_satoshis: 500)
        outpoints = results.map { |o| o[:outpoint] }
        expect(outpoints).to contain_exactly('aa.0', 'bb.0')
      end

      it 'returns an empty array when no spendable outputs exist in basket' do
        expect(store.find_spendable_outputs(basket: 'empty')).to be_empty
      end
    end

    describe '#update_output_state' do
      before do
        store.store_output(basket: 'default', outpoint: 'tx.0', spendable: true, satoshis: 1000)
      end

      it 'transitions to :spent and clears pending metadata' do
        store.update_output_state('tx.0', :spent)
        row = store.find_outputs(outpoint: 'tx.0', include_spent: true).first
        expect(row[:state]).to eq('spent')
      end

      it 'sets pending metadata when transitioning to :pending' do
        store.update_output_state('tx.0', :pending, pending_reference: 'ref-001', no_send: false)
        row = db[:wallet_outputs].where(outpoint: 'tx.0').first
        expect(row[:state]).to eq('pending')
        expect(row[:pending_since]).not_to be_nil
        expect(row[:pending_reference]).to eq('ref-001')
        expect(row[:no_send]).to be false
      end

      it 'sets no_send true when passed' do
        store.update_output_state('tx.0', :pending, pending_reference: 'ref-002', no_send: true)
        row = db[:wallet_outputs].where(outpoint: 'tx.0').first
        expect(row[:no_send]).to be true
      end

      it 'clears pending metadata when transitioning away from :pending' do
        store.update_output_state('tx.0', :pending, pending_reference: 'ref-001', no_send: true)
        store.update_output_state('tx.0', :spendable)
        row = db[:wallet_outputs].where(outpoint: 'tx.0').first
        expect(row[:state]).to eq('spendable')
        expect(row[:pending_since]).to be_nil
        expect(row[:pending_reference]).to be_nil
        expect(row[:no_send]).to be false
      end

      it 'removes pending keys from the JSONB data blob when clearing' do
        store.update_output_state('tx.0', :pending, pending_reference: 'ref-001', no_send: true)
        result = store.update_output_state('tx.0', :spendable)
        expect(result).not_to have_key(:pending_since)
        expect(result).not_to have_key(:pending_reference)
        expect(result).not_to have_key(:no_send)
      end

      it 'raises WalletError when the outpoint does not exist' do
        expect do
          store.update_output_state('nonexistent.0', :spent)
        end.to raise_error(BSV::Wallet::WalletError, /nonexistent\.0/)
      end

      it 'returns the updated output hash' do
        result = store.update_output_state('tx.0', :spent)
        expect(result).to be_a(Hash)
        expect(result[:outpoint]).to eq('tx.0')
      end
    end

    describe '#lock_utxos' do
      before do
        store.store_output(basket: 'default', outpoint: 'tx1.0', spendable: true, satoshis: 500)
        store.store_output(basket: 'default', outpoint: 'tx2.0', spendable: true, satoshis: 1000)
        store.store_output(basket: 'default', outpoint: 'tx3.0', spendable: false, satoshis: 200)
      end

      it 'locks spendable outputs and returns the locked outpoints' do
        locked = store.lock_utxos(%w[tx1.0 tx2.0], reference: 'ref-abc', no_send: false)
        expect(locked).to contain_exactly('tx1.0', 'tx2.0')
      end

      it 'returns empty array without hitting the database when given empty list' do
        expect(store.lock_utxos([], reference: 'ref')).to eq([])
      end

      it 'skips outputs not in spendable state' do
        locked = store.lock_utxos(%w[tx1.0 tx3.0], reference: 'ref', no_send: false)
        expect(locked).to contain_exactly('tx1.0')
      end

      it 'returns empty array when all requested outpoints are already pending' do
        store.update_output_state('tx1.0', :pending, pending_reference: 'first', no_send: false)
        locked = store.lock_utxos(['tx1.0'], reference: 'second', no_send: false)
        expect(locked).to be_empty
      end

      it 'sets state, pending_since, pending_reference, and no_send on the row' do
        store.lock_utxos(['tx1.0'], reference: 'ref-001', no_send: true)
        row = db[:wallet_outputs].where(outpoint: 'tx1.0').first
        expect(row[:state]).to eq('pending')
        expect(row[:pending_since]).not_to be_nil
        expect(row[:pending_reference]).to eq('ref-001')
        expect(row[:no_send]).to be true
      end

      it 'merges pending metadata into the JSONB data blob' do
        store.lock_utxos(['tx1.0'], reference: 'ref-001', no_send: false)
        result = store.find_outputs(outpoint: 'tx1.0', include_spent: true).first
        expect(result[:state]).to eq('pending')
        expect(result[:pending_reference]).to eq('ref-001')
      end

      it 'is safe under concurrent access — only one caller locks the outpoint' do
        results = []
        mutex = Mutex.new
        threads = Array.new(5) do
          Thread.new do
            locked = store.lock_utxos(['tx1.0'], reference: 'race', no_send: false)
            mutex.synchronize { results.concat(locked) }
          end
        end
        threads.each(&:join)

        # Exactly one thread should have locked it
        expect(results.count('tx1.0')).to eq(1)
      end

      it 'locks legacy rows with state NULL and spendable true' do
        db[:wallet_outputs].where(outpoint: 'tx1.0').update(state: nil, spendable: true)
        locked = store.lock_utxos(['tx1.0'], reference: 'ref', no_send: false)
        expect(locked).to include('tx1.0')
      end
    end

    describe '#release_stale_pending!' do
      before do
        store.store_output(basket: 'default', outpoint: 'tx1.0', spendable: true, satoshis: 500)
        store.store_output(basket: 'default', outpoint: 'tx2.0', spendable: true, satoshis: 500)
        store.store_output(basket: 'default', outpoint: 'tx3.0', spendable: true, satoshis: 500)
        store.store_output(basket: 'default', outpoint: 'tx4.0', spendable: true, satoshis: 500)
      end

      it 'returns 0 when no pending outputs exist' do
        expect(store.release_stale_pending!(timeout: 300)).to eq(0)
      end

      it 'releases stale pending outputs and returns count' do
        store.lock_utxos(%w[tx1.0 tx2.0], reference: 'ref', no_send: false)
        # Back-date pending_since to simulate stale locks
        db[:wallet_outputs]
          .where(outpoint: %w[tx1.0 tx2.0])
          .update(pending_since: Sequel.lit("NOW() - INTERVAL '600 seconds'"))

        released = store.release_stale_pending!(timeout: 300)
        expect(released).to eq(2)
      end

      it 'resets state to spendable and clears pending metadata on released rows' do
        store.lock_utxos(['tx1.0'], reference: 'ref', no_send: false)
        db[:wallet_outputs]
          .where(outpoint: 'tx1.0')
          .update(pending_since: Sequel.lit("NOW() - INTERVAL '600 seconds'"))

        store.release_stale_pending!(timeout: 300)

        row = db[:wallet_outputs].where(outpoint: 'tx1.0').first
        expect(row[:state]).to eq('spendable')
        expect(row[:pending_since]).to be_nil
        expect(row[:pending_reference]).to be_nil
        expect(row[:no_send]).to be false
      end

      it 'removes pending keys from the JSONB data blob on release' do
        store.lock_utxos(['tx1.0'], reference: 'ref', no_send: false)
        db[:wallet_outputs]
          .where(outpoint: 'tx1.0')
          .update(pending_since: Sequel.lit("NOW() - INTERVAL '600 seconds'"))

        store.release_stale_pending!(timeout: 300)

        result = store.find_outputs(outpoint: 'tx1.0').first
        expect(result).not_to have_key(:pending_since)
        expect(result).not_to have_key(:pending_reference)
        expect(result[:state]).to eq('spendable')
      end

      it 'does not release no_send pending outputs' do
        store.lock_utxos(['tx3.0'], reference: 'ref', no_send: true)
        db[:wallet_outputs]
          .where(outpoint: 'tx3.0')
          .update(pending_since: Sequel.lit("NOW() - INTERVAL '600 seconds'"))

        released = store.release_stale_pending!(timeout: 300)
        expect(released).to eq(0)

        row = db[:wallet_outputs].where(outpoint: 'tx3.0').first
        expect(row[:state]).to eq('pending')
      end

      it 'does not release pending outputs locked within the timeout window' do
        store.lock_utxos(['tx4.0'], reference: 'ref', no_send: false)
        # pending_since is just NOW() — well within 300s timeout

        released = store.release_stale_pending!(timeout: 300)
        expect(released).to eq(0)
      end

      it 'does not release outputs with pending_since = NULL' do
        store.lock_utxos(['tx1.0'], reference: 'ref', no_send: false)
        db[:wallet_outputs].where(outpoint: 'tx1.0').update(pending_since: nil)

        released = store.release_stale_pending!(timeout: 0)
        expect(released).to eq(0)
      end
    end

    describe '.migrate!' do
      it 'creates all five wallet tables' do
        described_class.migrate!(db)

        POSTGRES_WALLET_TABLES.each do |table|
          expect(db.table_exists?(table)).to be true
        end
      end

      it 'is idempotent — repeated calls do not error' do
        expect { 3.times { described_class.migrate!(db) } }.not_to raise_error
      end
    end
  end
end
