# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::MemoryStore do
  let(:store) { described_class.new }

  it 'includes StorageAdapter' do
    expect(described_class.ancestors).to include(BSV::Wallet::StorageAdapter)
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
        store.store_output(basket: 'my tokens', outpoint: 'abc.0')
        expect(store.delete_output('abc.0')).to be true
        expect(store.find_outputs(basket: 'my tokens', include_spent: true)).to be_empty
      end

      it 'returns false when the outpoint does not exist' do
        expect(store.delete_output('nonexistent.0')).to be false
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
        # Wrong serial number
        expect(store.delete_certificate(type: 'cert1', serial_number: 'wrong', certifier: 'abc')).to be false
        expect(store.find_certificates(certifiers: ['abc']).length).to eq(1)
      end
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

  describe 'pagination' do
    before do
      5.times { |i| store.store_action(labels: ['all'], txid: "tx#{i}") }
    end

    it 'limits results to the given limit' do
      results = store.find_actions(labels: ['all'], limit: 2)
      expect(results.length).to eq(2)
    end

    it 'skips results by offset' do
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
end
