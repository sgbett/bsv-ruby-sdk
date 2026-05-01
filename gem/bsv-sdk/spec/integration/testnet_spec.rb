# frozen_string_literal: true

require 'spec_helper'

# Integration tests that exercise the full SDK stack against live BSV testnet.
#
# Prerequisites:
#   - A funded testnet wallet (>= 3000 satoshis)
#   - Fund via: https://witnessonchain.com/faucet/tbsv
#   - Explorer: https://test.whatsonchain.com/
#
# Run with:
#   BSV_TESTNET_WIF='cXxx...' bundle exec rspec --tag testnet
#
# Each test group consumes a UTXO. Change returns to the same address,
# so the wallet stays funded across runs.
RSpec.describe 'Testnet integration', :testnet do
  def arc_url
    ENV.fetch('BSV_TESTNET_ARC_URL', 'https://testnet.arcade.gorillapool.io')
  end

  def dust_limit
    546
  end

  def fee_rate
    0.5
  end

  before(:context) do
    wif = ENV.fetch('BSV_TESTNET_WIF', nil)
    skip 'BSV_TESTNET_WIF not set — skipping testnet integration tests' unless wif

    @private_key = BSV::Primitives::PrivateKey.from_wif(wif)
    @public_key = @private_key.public_key
    @address = @public_key.address(network: :testnet)
    @locking_script = BSV::Script::Script.p2pkh_lock(@public_key.hash160)

    @utxos = TestnetWallet.fetch_utxos(@address)
    skip "No UTXOs for #{@address} — fund via #{TestnetWallet::FAUCET_URL}" if @utxos.empty?
  end

  let(:arc_protocol) do
    BSV::Network::Protocols::ARC.new(base_url: arc_url)
  end

  def arc_broadcast!(tx)
    result = arc_protocol.call(:broadcast, tx)
    raise "Broadcast failed: #{result.message}" unless result.success?

    result
  end

  def arc_status!(txid)
    result = arc_protocol.call(:get_tx_status, txid)
    raise "Status query failed: #{result.message}" unless result.success?

    result
  end

  def build_and_sign(inputs, outputs)
    tx = BSV::Transaction::Transaction.new
    inputs.each { |i| tx.add_input(i) }
    outputs.each { |o| tx.add_output(o) }
    tx.sign_all(@private_key)
    tx
  end

  def make_change_output(input_satoshis, spent_satoshis, output_count)
    fee = ((148 + (34 * (output_count + 1)) + 10) * fee_rate).ceil
    change = input_satoshis - spent_satoshis - fee
    raise "Insufficient funds for fee (need #{fee} more sats)" if change.negative?

    BSV::Transaction::TransactionOutput.new(
      satoshis: change,
      locking_script: @locking_script
    )
  end

  describe 'wallet setup' do
    it 'derives a valid testnet address with UTXOs' do
      expect(@address).to match(/\A[mn][a-km-zA-HJ-NP-Z1-9]+\z/)
      expect(@utxos).not_to be_empty
      expect(@utxos.first).to include('tx_hash', 'tx_pos', 'value')
    end
  end

  describe 'P2PKH transfer' do
    it 'builds, signs, broadcasts a self-payment, and queries status' do
      selected = TestnetWallet.select_utxos(@utxos, dust_limit + 200)
      input = TestnetWallet.utxo_to_input(selected.first, @locking_script)

      payment = BSV::Transaction::TransactionOutput.new(
        satoshis: dust_limit,
        locking_script: @locking_script
      )
      change = make_change_output(selected.first['value'], dust_limit, 1)
      tx = build_and_sign([input], [payment, change])

      expect(tx.txid_hex).to match(/\A[0-9a-f]{64}\z/)

      result = arc_broadcast!(tx)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data[:txid]).to eq(tx.txid_hex)

      status = arc_status!(tx.txid_hex)
      expect(status).to be_a(BSV::Network::Result::Success)
      expect(status.data[:txid]).to eq(tx.txid_hex)
    end
  end

  describe 'OP_RETURN attestation' do
    it 'broadcasts an OP_RETURN data transaction' do
      selected = TestnetWallet.select_utxos(@utxos, 400)
      input = TestnetWallet.utxo_to_input(selected.first, @locking_script)

      timestamp = "bsv-ruby-sdk test #{Time.now.utc.iso8601}"
      data_output = BSV::Transaction::TransactionOutput.new(
        satoshis: 0,
        locking_script: BSV::Script::Script.op_return(timestamp)
      )
      change = make_change_output(selected.first['value'], 0, 1)
      tx = build_and_sign([input], [data_output, change])

      result = arc_broadcast!(tx)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data[:txid]).to eq(tx.txid_hex)
    end
  end

  describe 'round-trip serialisation' do
    it 'broadcasts a tx, fetches raw hex from WoC, and parses back identically' do
      selected = TestnetWallet.select_utxos(@utxos, dust_limit + 200)
      input = TestnetWallet.utxo_to_input(selected.first, @locking_script)

      payment = BSV::Transaction::TransactionOutput.new(
        satoshis: dust_limit,
        locking_script: @locking_script
      )
      change = make_change_output(selected.first['value'], dust_limit, 1)
      tx = build_and_sign([input], [payment, change])

      original_hex = tx.to_hex
      original_txid = tx.txid_hex

      arc_broadcast!(tx)

      # Poll WoC until the transaction is indexed (up to 15 seconds)
      fetched_hex = nil
      5.times do
        sleep 3
        fetched_hex = TestnetWallet.fetch_raw_tx_if_available(original_txid)
        break if fetched_hex
      end
      raise "Transaction #{original_txid} not found on WoC after 15 seconds" unless fetched_hex

      expect(fetched_hex).to eq(original_hex)

      parsed = BSV::Transaction::Transaction.from_hex(fetched_hex)
      expect(parsed.txid_hex).to eq(original_txid)
      expect(parsed.to_hex).to eq(original_hex)
    end
  end
end
