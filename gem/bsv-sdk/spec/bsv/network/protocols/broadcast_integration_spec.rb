# frozen_string_literal: true

# Live broadcast integration spec — submits one signed transaction to the BSV
# Association Broadcaster (Arcade), GorillaPool's ARC and, when a key is
# available, TAAL's ARC, end-to-end with a real funded mainnet WIF.
#
# The Broadcaster goes first so its submit parsing sees a fresh submission; the
# later services then report the transaction as already known, which they accept.
#
# Required env vars:
#   BSV_LIVE_TEST_WIF — funded mainnet WIF (needs at least 1000 sats)
# Optional env vars:
#   TAAL_API_KEY — TAAL ARC API key; TAAL requires one on everything but
#                  /v1/policy, so without it only the TAAL leg is skipped
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
      skip 'WoC rate-limited — set BSV_LIVE_TEST_PREVOUT to bypass' if result.code == '429'
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

    t = BSV::Transaction::Tx.new
    t.add_input(input)
    t.add_output(output)
    t.sign_all(private_key)
    t
  end
  let(:taal_api_key) { ENV.fetch('TAAL_API_KEY', nil) }
  let(:services) do
    {
      'BSV Association Broadcaster' => BSV::Network::Providers::BSVAssociation.mainnet,
      'GorillaPool ARC' => BSV::Network::Providers::GorillaPool.mainnet,
      'TAAL ARC' => (BSV::Network::Providers::TAAL.mainnet(api_key: taal_api_key) if taal_api_key)
    }
  end

  before { skip 'set BSV_LIVE_TEST_WIF to run' unless wif }

  def rejected?(result)
    BSV::Network::Protocols::ARC.rejected_tx_status?(result.data['txStatus'])
  end

  it 'broadcasts one transaction through every service and round-trips the txid' do
    txid = tx.txid_hex

    services.each do |name, provider|
      next warn("#{name} leg skipped: set TAAL_API_KEY to include it") unless provider

      result = provider.call(:broadcast, tx)
      skip "#{name} rate-limited (429)" if result.code == '429'

      aggregate_failures("#{name} broadcast") do
        expect(result).to be_http_success
        expect(result.data['txid']).to eq(txid)
        expect(rejected?(result)).to be(false)
      end
    end

    sleep 2

    services.each do |name, provider|
      next unless provider

      status = provider.call(:get_tx_status, txid)
      skip "#{name} rate-limited (429)" if status.code == '429'

      aggregate_failures("#{name} status") do
        expect(status).to be_http_success
        expect(status.data['txid']).to eq(txid)
        expect(rejected?(status)).to be(false)
      end
    end
  end
end
