# frozen_string_literal: true

# x402_client.rb
#
# Minimal client demonstrating the BSV::X402::Client auto-pay flow.
#
# This example is illustrative — it does not make real network requests.
# Substitute real UTXOs, a signing key, and an HTTP endpoint to use live.
#
# Usage:
#   bundle exec ruby examples/x402_client.rb

require 'bsv-x402'

# ---------------------------------------------------------------------------
# 1. Client key material
#
#    The client needs:
#      - One or more funding UTXOs (to cover the payment amount plus miner fee)
#      - A nonce unlocker: a callable that signs the nonce input issued by
#        the server in its challenge.
#      - Optionally, a change locking script to receive unspent funds back.
# ---------------------------------------------------------------------------
client_key = BSV::Primitives::PrivateKey.generate
client_script = BSV::Script::Script.p2pkh_lock(client_key.public_key.hash160)

# The nonce UTXO locking script is server-controlled.  The server issues a
# nonce locked to a key it owns, and the client must spend it.  The
# nonce_unlocker callable receives the partially-built transaction and the
# input index, and must return the unlocking script for that input.
#
# When the server locks the nonce to the *client's* key (a common pattern),
# the client signs with P2PKH:
nonce_key      = BSV::Primitives::PrivateKey.generate # matches nonce UTXO locking script
nonce_unlocker = lambda do |tx, idx|
  BSV::Transaction::P2PKH.new(nonce_key).sign(tx, idx)
end

# Funding UTXOs — each element is a plain Hash describing a spendable output.
# In production, fetch these from your wallet or UTXO index.
funding_utxos = [
  {
    txid: 'ab' * 32, # transaction ID (hex, big-endian display order)
    vout: 0,                    # output index
    satoshis: 10_000,           # value in satoshis
    locking_script_hex: client_script.to_hex,
    private_key: client_key     # key to sign this input
  }
]

# Change — any surplus after payment + fee is returned here.
change_key        = BSV::Primitives::PrivateKey.generate
change_script_hex = BSV::Script::Script.p2pkh_lock(change_key.public_key.hash160).to_hex

# ---------------------------------------------------------------------------
# 2. Optional broadcaster
#
#    Set a broadcaster if you want the payment transaction broadcast to the
#    BSV network before the proof is submitted.  The broadcaster must respond
#    to #broadcast(transaction).
#
#    When broadcaster is nil (the default), the transaction is embedded in
#    the proof but not broadcast independently.  The server receives the raw
#    bytes via the proof and may broadcast it itself.
# ---------------------------------------------------------------------------
broadcaster = nil # replace with BSV::Network::ARC.new(...) or similar

# ---------------------------------------------------------------------------
# 3. Construct the client
# ---------------------------------------------------------------------------
client = BSV::X402::Client.new(
  funding_utxos: funding_utxos,
  nonce_unlocker: nonce_unlocker,
  change_locking_script_hex: change_script_hex,
  broadcaster: broadcaster,

  # max_retries controls how many payment attempts the client makes if the
  # server keeps returning 402 (e.g. stale challenge). Default is 1.
  max_retries: 1,

  # auto_pay: false disables automatic payment — the client returns the raw
  # 402 response to the caller instead of paying.
  auto_pay: true
)

# ---------------------------------------------------------------------------
# 4. Make a request — the client handles the 402 flow automatically.
#
#    Flow:
#      a. GET /api/premium
#      b. Server returns 402 + X402-Challenge header
#      c. Client decodes the challenge, builds the payment transaction,
#         optionally broadcasts it, builds the proof, and retries.
#      d. GET /api/premium with X402-Proof header
#      e. Server verifies the proof, returns 200 (or another 402 on failure)
# ---------------------------------------------------------------------------
begin
  status, _headers, body = client.get('http://localhost:9292/api/premium')
  puts "Status: #{status}"
  puts "Body:   #{body}"
rescue BSV::X402::ChallengeExpiredError => e
  # The server issued an already-expired challenge — retry the request.
  puts "Challenge expired: #{e.message}"
rescue BSV::X402::InsufficientFundsError => e
  # Not enough satoshis in the funding UTXOs to cover payment + fee.
  puts "Insufficient funds: #{e.message}"
rescue BSV::X402::PaymentRetryExhaustedError => e
  # The client tried max_retries times and the server kept returning 402.
  puts "Max retries exceeded: #{e.message}"
end

# ---------------------------------------------------------------------------
# 5. POST request with a body
#
#    The request body is SHA-256 hashed and bound to the challenge, so the
#    server can verify the client paid for exactly this request.
# ---------------------------------------------------------------------------
begin
  payload = '{"city":"lisbon"}'
  status, _headers, body = client.post(
    'http://localhost:9292/api/data',
    body: payload,
    headers: { 'content-type' => 'application/json' }
  )
  puts "POST Status: #{status}"
  puts "POST Body:   #{body}"
rescue BSV::X402::Error => e
  puts "x402 error: #{e.class}: #{e.message}"
end
