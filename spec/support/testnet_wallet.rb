# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

# Test-only helper for interacting with WhatsOnChain testnet API.
# Not shipped in the gem.
module TestnetWallet
  WOC_BASE = 'https://api.whatsonchain.com/v1/bsv/test'
  FAUCET_URL = 'https://witnessonchain.com/faucet/tbsv'

  module_function

  # Fetch unspent outputs for a testnet address.
  # Returns an array of hashes: { 'tx_hash' => ..., 'tx_pos' => ..., 'value' => ... }
  def fetch_utxos(address)
    uri = URI("#{WOC_BASE}/address/#{address}/unspent")
    response = Net::HTTP.get_response(uri)
    raise "WoC UTXOs request failed (#{response.code}): #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  # Fetch raw transaction hex by txid. Raises on HTTP error.
  def fetch_raw_tx(txid)
    uri = URI("#{WOC_BASE}/tx/#{txid}/hex")
    response = Net::HTTP.get_response(uri)
    raise "WoC raw tx request failed (#{response.code}): #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    response.body.strip
  end

  # Like fetch_raw_tx but returns nil on 404 (not yet indexed).
  def fetch_raw_tx_if_available(txid)
    uri = URI("#{WOC_BASE}/tx/#{txid}/hex")
    response = Net::HTTP.get_response(uri)
    return nil if response.code == '404'
    raise "WoC raw tx request failed (#{response.code}): #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    response.body.strip
  end

  # Greedy UTXO selection. Picks UTXOs until the target is met.
  # Raises with faucet instructions if insufficient funds.
  def select_utxos(utxos, min_satoshis)
    sorted = utxos.sort_by { |u| -u['value'] }
    selected = []
    total = 0

    sorted.each do |utxo|
      selected << utxo
      total += utxo['value']
      break if total >= min_satoshis
    end

    if total < min_satoshis
      raise "Insufficient testnet funds (have #{total}, need #{min_satoshis}). " \
            "Fund the address via #{FAUCET_URL}"
    end

    selected
  end

  # Convert a WoC UTXO hash into a TransactionInput with source metadata attached.
  def utxo_to_input(utxo, locking_script)
    input = BSV::Transaction::TransactionInput.new(
      prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex(utxo['tx_hash']),
      prev_tx_out_index: utxo['tx_pos']
    )
    input.source_satoshis = utxo['value']
    input.source_locking_script = locking_script
    input
  end
end
