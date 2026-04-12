# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'
require 'tmpdir'

RSpec.describe BSV::Wallet::FileStore do
  let(:tmpdir) { Dir.mktmpdir('bsv-wallet-test') }
  let(:store) { described_class.new(dir: tmpdir) }

  after { FileUtils.rm_rf(tmpdir) }

  it_behaves_like 'a storage adapter'

  describe '#initialize' do
    it 'creates the directory if it does not exist' do
      new_dir = File.join(tmpdir, 'nested', 'wallet')
      described_class.new(dir: new_dir)
      expect(Dir.exist?(new_dir)).to be true
    end

    it 'uses BSV_WALLET_DIR env var when no dir given' do
      env_dir = File.join(tmpdir, 'from-env')
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('BSV_WALLET_DIR', anything).and_return(env_dir)
      described_class.new
      expect(Dir.exist?(env_dir)).to be true
    end
  end

  describe 'persistence' do
    it 'persists actions across instances' do
      store.store_action({ labels: ['test'], txid: 'abc', description: 'test action here' })

      reloaded = described_class.new(dir: tmpdir)
      actions = reloaded.find_actions({ labels: ['test'] })
      expect(actions.length).to eq(1)
      expect(actions.first[:txid]).to eq('abc')
    end

    it 'persists outputs across instances' do
      store.store_output({ basket: 'my test tokens', outpoint: 'def.0', satoshis: 1000, spendable: true })

      reloaded = described_class.new(dir: tmpdir)
      outputs = reloaded.find_outputs({ basket: 'my test tokens' })
      expect(outputs.length).to eq(1)
      expect(outputs.first[:satoshis]).to eq(1000)
    end

    it 'persists certificates across instances' do
      store.store_certificate({ type: 'cert1', certifier: 'abc', serial_number: 's1', subject: 'xyz' })

      reloaded = described_class.new(dir: tmpdir)
      certs = reloaded.find_certificates({ certifiers: ['abc'] })
      expect(certs.length).to eq(1)
      expect(certs.first[:serial_number]).to eq('s1')
    end

    it 'persists output deletion' do
      store.store_output({ basket: 'token vault', outpoint: 'aaa.0', spendable: true })
      store.delete_output('aaa.0')

      reloaded = described_class.new(dir: tmpdir)
      outputs = reloaded.find_outputs({ basket: 'token vault' })
      expect(outputs).to be_empty
    end

    it 'persists certificate deletion' do
      store.store_certificate({ type: 't1', certifier: 'c1', serial_number: 's1' })
      store.delete_certificate(type: 't1', serial_number: 's1', certifier: 'c1')

      reloaded = described_class.new(dir: tmpdir)
      certs = reloaded.find_certificates({ certifiers: ['c1'], types: ['t1'] })
      expect(certs).to be_empty
    end
  end

  describe 'corrupt file handling' do
    it 'recovers from invalid JSON' do
      File.write(File.join(tmpdir, 'actions.json'), 'not json{{{')

      reloaded = described_class.new(dir: tmpdir)
      expect(reloaded.find_actions({})).to be_empty
    end

    it 'recovers from non-array JSON' do
      File.write(File.join(tmpdir, 'outputs.json'), '{"not": "an array"}')

      reloaded = described_class.new(dir: tmpdir)
      expect(reloaded.find_outputs({ basket: 'anything' })).to be_empty
    end
  end

  describe 'atomic writes' do
    it 'does not leave .tmp files after write' do
      store.store_action({ labels: ['test'], txid: 'abc', description: 'atomicity test' })

      tmp_files = Dir.glob(File.join(tmpdir, '*.tmp'))
      expect(tmp_files).to be_empty
    end
  end

  describe 'filtering and pagination' do
    it 'supports the same queries as MemoryStore' do
      store.store_action({ labels: %w[payment urgent], txid: 'tx1' })
      store.store_action({ labels: ['payment'], txid: 'tx2' })

      any_results = store.find_actions({ labels: ['urgent'] })
      expect(any_results.length).to eq(1)

      all_results = store.find_actions({ labels: %w[payment urgent], label_query_mode: 'all' })
      expect(all_results.length).to eq(1)
      expect(all_results.first[:txid]).to eq('tx1')
    end

    it 'counts correctly' do
      3.times { |i| store.store_output({ basket: 'count test', outpoint: "tx.#{i}", spendable: true }) }
      expect(store.count_outputs({ basket: 'count test' })).to eq(3)
    end
  end

  describe 'UTXO state tracking persistence' do
    it 'persists a state change across reload' do
      store.store_output({ outpoint: 'tx0:0', satoshis: 500, state: :spendable })
      store.update_output_state('tx0:0', :pending)

      reloaded = described_class.new(dir: tmpdir)
      results = reloaded.find_spendable_outputs
      expect(results).to be_empty
    end

    it 'persists :spent state across reload' do
      store.store_output({ outpoint: 'tx0:0', satoshis: 200, state: :spendable })
      store.update_output_state('tx0:0', :spent)

      reloaded = described_class.new(dir: tmpdir)
      results = reloaded.find_spendable_outputs
      expect(results).to be_empty
    end

    it 'persists state restored to :spendable across reload' do
      store.store_output({ outpoint: 'tx0:0', satoshis: 300, state: :pending })
      store.update_output_state('tx0:0', :spendable)

      reloaded = described_class.new(dir: tmpdir)
      results = reloaded.find_spendable_outputs
      expect(results.length).to eq(1)
      expect(results.first[:satoshis]).to eq(300)
    end

    it 'does not leave .tmp files after update_output_state' do
      store.store_output({ outpoint: 'tx0:0', satoshis: 100, state: :spendable })
      store.update_output_state('tx0:0', :pending)

      tmp_files = Dir.glob(File.join(tmpdir, '*.tmp'))
      expect(tmp_files).to be_empty
    end
  end
end
