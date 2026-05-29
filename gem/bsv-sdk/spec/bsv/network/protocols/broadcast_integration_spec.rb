# frozen_string_literal: true

# Live broadcast integration spec — exercises both TAAL ARC and GorillaPool Arcade
# end-to-end with a real funded mainnet WIF.
#
# Required env vars:
#   BSV_LIVE_TEST_WIF — funded mainnet WIF (needs at least 1000 sats)
# Optional env vars:
#   TAAL_API_KEY — TAAL ARC API key (free tier works; unauthenticated may 429)
#
# UTXO sourcing:
#   Uses Providers::WhatsOnChain.mainnet.call(:get_utxos, address).
#   If WoC returns 429 (rate-limited), the whole group is skipped cleanly.
#   Fallback: set BSV_LIVE_TEST_PREVOUT=<dtxid_hex>:<vout>:<satoshis> to bypass WoC.
#
# Run:
#   bundle exec rspec spec/bsv/network/protocols/broadcast_integration_spec.rb --tag integration

require 'spec_helper'

RSpec.describe 'Live broadcast', :integration do # rubocop:disable RSpec/DescribeClass
  let(:wif) { ENV.fetch('BSV_LIVE_TEST_WIF', nil) }
  let(:private_key) { BSV::Primitives::PrivateKey.from_wif(wif) }
  let(:public_key)  { private_key.public_key }
  let(:address)     { public_key.address }
  let(:lock_script) { BSV::Script::Script.p2pkh_lock(public_key.hash160) }
  let(:utxo) do
    prevout_env = ENV.fetch('BSV_LIVE_TEST_PREVOUT', nil)
    if prevout_env
      parts = prevout_env.split(':')
      raise 'BSV_LIVE_TEST_PREVOUT must be <dtxid_hex>:<vout>:<satoshis>' unless parts.length == 3

      { 'tx_hash' => parts[0], 'tx_pos' => Integer(parts[1]), 'value' => Integer(parts[2]) }
    else
      woc = BSV::Network::Providers::WhatsOnChain.mainnet
      result = woc.call(:get_utxos, address)
      skip 'WoC rate-limited — set BSV_LIVE_TEST_PREVOUT to bypass' if result.http_response.code == '429'
      raise "WoC UTXO fetch failed: #{result.error_message}" unless result.http_success?

      candidates = result.data.select { |u| u['value'] >= 1000 }
      skip "No UTXOs >= 1000 sats for #{address} — fund the address first" if candidates.empty?

      candidates.max_by { |u| u['value'] }
    end
  end
  let(:tx) do
    input = BSV::Transaction::TransactionInput.new(
      prev_wtxid: BSV::Transaction::TransactionInput.wtxid_from_hex(utxo['tx_hash']),
      prev_tx_out_index: utxo['tx_pos']
    )
    input.source_satoshis = utxo['value']
    input.source_locking_script = lock_script

    fee = 100
    change = utxo['value'] - fee
    raise "UTXO too small after fee (#{utxo['value']} sats, fee #{fee})" if change < 1

    output = BSV::Transaction::TransactionOutput.new(satoshis: change, locking_script: lock_script)

    t = BSV::Transaction::Transaction.new
    t.add_input(input)
    t.add_output(output)
    t.sign_all(private_key)
    t
  end
  let(:taal) do
    BSV::Network::Providers::TAAL.mainnet(api_key: ENV.fetch('TAAL_API_KEY', nil))
  end
  let(:gorilla_pool) { BSV::Network::Providers::GorillaPool.mainnet }

  before { skip 'set BSV_LIVE_TEST_WIF to run' unless wif }

  it 'broadcasts via TAAL ARC' do
    result = taal.call(:broadcast, tx)
    expect(result).to be_http_success
    expect(result.data['txStatus']).to be_in(%w[SEEN_ON_NETWORK RECEIVED MINED])
  end

  it 'broadcasts the same tx via GorillaPool Arcade (idempotent re-broadcast)' do
    taal.call(:broadcast, tx)

    result = gorilla_pool.call(:broadcast, tx)
    expect(result).to be_http_success
    expect(result.data['status']).to be_in(['submitted', 'already submitted'])
  end

  it 'TAAL get_tx_status round-trips a freshly-broadcast txid' do
    broadcast = taal.call(:broadcast, tx)
    expect(broadcast).to be_http_success

    txid = tx.txid_hex
    sleep 2

    status = taal.call(:get_tx_status, txid)
    expect(status).to be_http_success
    expect(status.data['txid']).to eq(txid)
    expect(status.data['txStatus']).to be_in(%w[RECEIVED SEEN_ON_NETWORK MINED])
  end
end
