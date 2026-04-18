# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe 'WalletClient#wallet_health and #recover_failed_broadcast' do
  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  let(:store) { BSV::Wallet::MemoryStore.new }

  def build_registry_with_is_utxo(responses)
    registry = BSV::Network::Registry.new
    provider = Class.new(BSV::Network::Provider) do
      provides :is_utxo

      define_method(:call_is_utxo) do |txid, vout|
        responses["#{txid}.#{vout}"]
      end
    end.new
    registry.register(provider)
    registry
  end

  def build_registry_with_tx_status(responses)
    registry = BSV::Network::Registry.new
    provider = Class.new(BSV::Network::Provider) do
      provides :get_tx_status

      define_method(:call_get_tx_status) do |txid|
        responses[txid]
      end
    end.new
    registry.register(provider)
    registry
  end

  def wallet_with_registry(registry)
    BSV::Wallet::WalletClient.new(private_key, storage: store, network: registry)
  end

  def plain_wallet
    BSV::Wallet::WalletClient.new(private_key, storage: store)
  end

  def seed_output(outpoint:, satoshis: 1_000, basket: 'default', state: :spendable)
    store.store_output(outpoint: outpoint, satoshis: satoshis, basket: basket, state: state)
  end

  def seed_action(txid:, status: 'completed')
    store.store_action(txid: txid, description: 'test', status: status, labels: [])
  end

  # -------------------------------------------------------------------------
  # wallet_health — storage-level (verify: false)
  # -------------------------------------------------------------------------

  describe '#wallet_health without verify' do
    let(:client) { plain_wallet }

    it 'returns zero counts when no outputs exist' do
      result = client.wallet_health
      expect(result[:total_outputs]).to eq(0)
      expect(result[:total_satoshis]).to eq(0)
      expect(result[:baskets]).to be_empty
    end

    it 'counts spendable outputs correctly' do
      seed_output(outpoint: 'aa.0', satoshis: 1_000)
      seed_output(outpoint: 'bb.0', satoshis: 2_000)
      result = client.wallet_health
      expect(result[:total_outputs]).to eq(2)
      expect(result[:total_satoshis]).to eq(3_000)
    end

    it 'groups outputs by basket' do
      seed_output(outpoint: 'aa.0', satoshis: 1_000, basket: 'default')
      seed_output(outpoint: 'bb.0', satoshis: 500,  basket: 'tokens')
      seed_output(outpoint: 'cc.0', satoshis: 750,  basket: 'tokens')
      result = client.wallet_health
      expect(result[:baskets]['default'][:count]).to eq(1)
      expect(result[:baskets]['default'][:satoshis]).to eq(1_000)
      expect(result[:baskets]['tokens'][:count]).to eq(2)
      expect(result[:baskets]['tokens'][:satoshis]).to eq(1_250)
    end

    it 'excludes pending outputs' do
      seed_output(outpoint: 'aa.0', satoshis: 1_000, state: :spendable)
      seed_output(outpoint: 'bb.0', satoshis: 2_000, state: :pending)
      result = client.wallet_health
      expect(result[:total_outputs]).to eq(1)
    end

    it 'excludes spent outputs' do
      seed_output(outpoint: 'aa.0', satoshis: 1_000, state: :spent)
      result = client.wallet_health
      expect(result[:total_outputs]).to eq(0)
    end

    it 'does not include :verified or :quarantined keys' do
      result = client.wallet_health
      expect(result).not_to have_key(:verified)
      expect(result).not_to have_key(:quarantined)
    end
  end

  # -------------------------------------------------------------------------
  # wallet_health — with verify: true, all UTXOs valid
  # -------------------------------------------------------------------------

  describe '#wallet_health(verify: true) with all UTXOs valid' do
    it 'returns verified count equal to output count and empty quarantined list' do
      registry = build_registry_with_is_utxo(
        'aabb.0' => BSV::Network::Result::Success.new(data: true),
        'ccdd.1' => BSV::Network::Result::Success.new(data: true)
      )
      client = wallet_with_registry(registry)
      seed_output(outpoint: 'aabb.0', satoshis: 1_000)
      seed_output(outpoint: 'ccdd.1', satoshis: 2_000)

      result = client.wallet_health(verify: true)
      expect(result[:verified]).to eq(2)
      expect(result[:quarantined]).to be_empty
      expect(result[:verification_errors]).to be_empty
    end
  end

  # -------------------------------------------------------------------------
  # wallet_health — with verify: true, some UTXOs spent
  # -------------------------------------------------------------------------

  describe '#wallet_health(verify: true) with some UTXOs spent on-chain' do
    it 'quarantines outputs that are no longer unspent' do
      registry = build_registry_with_is_utxo(
        'aabb.0' => BSV::Network::Result::Success.new(data: true),
        'ccdd.1' => BSV::Network::Result::Success.new(data: false)
      )
      client = wallet_with_registry(registry)
      seed_output(outpoint: 'aabb.0', satoshis: 1_000)
      seed_output(outpoint: 'ccdd.1', satoshis: 2_000)

      result = client.wallet_health(verify: true)
      expect(result[:quarantined]).to eq(['ccdd.1'])
      expect(result[:verified]).to eq(1)
    end

    it 'updates quarantined output state to :invalid in storage' do
      registry = build_registry_with_is_utxo(
        'ccdd.1' => BSV::Network::Result::Success.new(data: false)
      )
      client = wallet_with_registry(registry)
      seed_output(outpoint: 'ccdd.1', satoshis: 2_000)

      client.wallet_health(verify: true)

      # After quarantine, the output should no longer appear as spendable
      remaining = store.find_spendable_outputs
      expect(remaining.map { |o| o[:outpoint] }).not_to include('ccdd.1')
    end
  end

  # -------------------------------------------------------------------------
  # wallet_health — with verify: true, no :is_utxo provider
  # -------------------------------------------------------------------------

  describe '#wallet_health(verify: true) with no :is_utxo provider' do
    it 'raises UnsupportedActionError' do
      client = plain_wallet
      seed_output(outpoint: 'aabb.0', satoshis: 1_000)
      expect do
        client.wallet_health(verify: true)
      end.to raise_error(BSV::Wallet::UnsupportedActionError)
    end
  end

  # -------------------------------------------------------------------------
  # wallet_health — with verify: true, :is_utxo error on one output
  # -------------------------------------------------------------------------

  describe '#wallet_health(verify: true) with :is_utxo error on one output' do
    it 'logs a warning, continues checking remaining outputs, and includes error in report' do
      registry = build_registry_with_is_utxo(
        'aabb.0' => BSV::Network::Result::Error.new('timeout'),
        'ccdd.1' => BSV::Network::Result::Success.new(data: true)
      )
      client = wallet_with_registry(registry)
      seed_output(outpoint: 'aabb.0', satoshis: 1_000)
      seed_output(outpoint: 'ccdd.1', satoshis: 2_000)

      result = client.wallet_health(verify: true)
      expect(result[:verification_errors].size).to eq(1)
      expect(result[:verification_errors].first[:outpoint]).to eq('aabb.0')
      expect(result[:verified]).to eq(1)
      expect(result[:quarantined]).to be_empty
    end
  end

  # -------------------------------------------------------------------------
  # recover_failed_broadcast — mined transaction
  # -------------------------------------------------------------------------

  describe '#recover_failed_broadcast with mined transaction' do
    it 'promotes the action to unproven and returns recovered: true' do
      txid = "#{'aabbcc' * 10}aabb"
      registry = build_registry_with_tx_status(
        txid => BSV::Network::Result::Success.new(data: { tx_status: 'MINED' })
      )
      client = wallet_with_registry(registry)
      seed_action(txid: txid, status: 'failed')

      result = client.recover_failed_broadcast(txid)
      expect(result[:recovered]).to be(true)
      expect(result[:new_status]).to eq('unproven')
      expect(result[:on_chain_status]).to eq('MINED')
    end

    it 'updates the action status in storage' do
      txid = "#{'aabbcc' * 10}aabb"
      registry = build_registry_with_tx_status(
        txid => BSV::Network::Result::Success.new(data: { tx_status: 'MINED' })
      )
      client = wallet_with_registry(registry)
      seed_action(txid: txid, status: 'failed')

      client.recover_failed_broadcast(txid)

      actions = store.find_actions({ limit: 100, offset: 0 })
      action = actions.find { |a| a[:txid] == txid }
      expect(action[:status]).to eq('unproven')
    end
  end

  # -------------------------------------------------------------------------
  # recover_failed_broadcast — seen on network
  # -------------------------------------------------------------------------

  describe '#recover_failed_broadcast with SEEN_ON_NETWORK status' do
    it 'promotes the action to unproven' do
      txid = "#{'ccddee' * 10}ccdd"
      registry = build_registry_with_tx_status(
        txid => BSV::Network::Result::Success.new(data: { tx_status: 'SEEN_ON_NETWORK' })
      )
      client = wallet_with_registry(registry)
      seed_action(txid: txid, status: 'pending')

      result = client.recover_failed_broadcast(txid)
      expect(result[:recovered]).to be(true)
      expect(result[:new_status]).to eq('unproven')
    end
  end

  # -------------------------------------------------------------------------
  # recover_failed_broadcast — truly failed transaction
  # -------------------------------------------------------------------------

  describe '#recover_failed_broadcast with transaction not found on-chain' do
    it 'returns recovered: false with reason not_found_on_chain' do
      txid = "#{'eeff00' * 10}eeff"
      registry = build_registry_with_tx_status(
        txid => BSV::Network::Result::NotFound.new
      )
      client = wallet_with_registry(registry)
      seed_action(txid: txid, status: 'failed')

      result = client.recover_failed_broadcast(txid)
      expect(result[:recovered]).to be(false)
      expect(result[:reason]).to eq('not_found_on_chain')
    end
  end

  # -------------------------------------------------------------------------
  # recover_failed_broadcast — pending in mempool
  # -------------------------------------------------------------------------

  describe '#recover_failed_broadcast with transaction still pending in mempool' do
    it 'returns recovered: false with current on_chain_status' do
      txid = "#{'112233' * 10}1122"
      registry = build_registry_with_tx_status(
        txid => BSV::Network::Result::Success.new(data: { tx_status: 'ANNOUNCED_TO_NETWORK' })
      )
      client = wallet_with_registry(registry)
      seed_action(txid: txid, status: 'pending')

      result = client.recover_failed_broadcast(txid)
      expect(result[:recovered]).to be(false)
      expect(result[:on_chain_status]).to eq('ANNOUNCED_TO_NETWORK')
    end
  end

  # -------------------------------------------------------------------------
  # recover_failed_broadcast — already completed
  # -------------------------------------------------------------------------

  describe '#recover_failed_broadcast with already-completed action' do
    it 'returns recovered: false without making network calls' do
      txid = "#{'445566' * 10}4455"
      # No provider registered — if a network call were made it would raise
      client = plain_wallet
      seed_action(txid: txid, status: 'completed')

      result = client.recover_failed_broadcast(txid)
      expect(result[:recovered]).to be(false)
      expect(result[:status]).to eq('completed')
    end
  end

  # -------------------------------------------------------------------------
  # recover_failed_broadcast — unknown txid
  # -------------------------------------------------------------------------

  describe '#recover_failed_broadcast with unknown txid' do
    it 'raises WalletError' do
      client = plain_wallet
      expect do
        client.recover_failed_broadcast('nonexistent_txid')
      end.to raise_error(BSV::Wallet::WalletError, /not found/i)
    end
  end

  # -------------------------------------------------------------------------
  # recover_failed_broadcast — no :get_tx_status provider
  # -------------------------------------------------------------------------

  describe '#recover_failed_broadcast with no :get_tx_status provider' do
    it 'raises UnsupportedActionError' do
      txid = "#{'778899' * 10}7788"
      client = plain_wallet
      seed_action(txid: txid, status: 'failed')
      expect do
        client.recover_failed_broadcast(txid)
      end.to raise_error(BSV::Wallet::UnsupportedActionError)
    end
  end
end
