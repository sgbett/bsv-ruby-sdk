# frozen_string_literal: true

# x402_rack_app.rb
#
# Minimal Rack application demonstrating BSV::X402::Middleware.
#
# This example is illustrative — it does not require a live BSV node or
# real UTXOs. Substitute your own nonce provider and payee key to deploy.
#
# Run with:
#   gem install rack bsv-sdk
#   bundle exec rackup examples/x402_rack_app.rb -p 9292

require 'bsv-x402'
require 'rack'
require 'json'

# ---------------------------------------------------------------------------
# 1. Generate a payee key (server-side — holds the private key for the
#    locking script that clients must pay).
#    In production, load this from a keystore, not generated at startup.
# ---------------------------------------------------------------------------
payee_key        = BSV::Primitives::PrivateKey.generate
payee_script_hex = BSV::Script::Script.p2pkh_lock(payee_key.public_key.hash160).to_hex

# ---------------------------------------------------------------------------
# 2. Nonce provider — responsible for issuing fresh UTXOs that clients must
#    spend in their payment transactions to prevent replay.
#
#    StaticNonceProvider is provided for development/testing only.
#    In production, use a database-backed provider that atomically reserves
#    one UTXO per request and marks it spent after verification.
# ---------------------------------------------------------------------------
nonce_key  = BSV::Primitives::PrivateKey.generate
nonce_utxo = BSV::X402::NonceUTXO.new(
  txid: 'aa' * 32, # replace with a real on-chain txid
  vout: 0,
  satoshis: 10,
  locking_script_hex: BSV::Script::Script.p2pkh_lock(nonce_key.public_key.hash160).to_hex
)
nonce_provider = BSV::X402::StaticNonceProvider.new(nonce_utxo)

# ---------------------------------------------------------------------------
# 3. Global x402 configuration — applies to every protected route unless
#    a per-route override is supplied in the middleware DSL block.
# ---------------------------------------------------------------------------
BSV::X402.configure do |config|
  config.payee_locking_script_hex = payee_script_hex
  config.amount_sats              = 100     # default price per request (satoshis)
  config.expires_in               = 300     # challenge validity window (seconds)
  config.nonce_provider           = nonce_provider
  config.bound_headers            = []      # no extra headers bound by default

  # Optional: fire a callback after each successful payment.
  config.on_payment_verified = lambda do |_env, result|
    puts "[x402] payment verified — txid: #{result&.step || 'n/a'}"
  end

  # Optional: verify mempool acceptance before responding (requires a node).
  # config.settlement_verifier = ->(raw_tx_bytes) { MyNode.test_mempool_accept(raw_tx_bytes) }
end

# ---------------------------------------------------------------------------
# 4. Inner Rack application — the content behind the paywall.
# ---------------------------------------------------------------------------
inner_app = lambda do |env|
  request = Rack::Request.new(env)
  body    = JSON.generate(
    path: request.path,
    message: 'You have paid — here is the premium content.',
    timestamp: Time.now.to_i
  )
  [200, { 'content-type' => 'application/json' }, [body]]
end

# ---------------------------------------------------------------------------
# 5. Wrap the inner app with x402 middleware.
#
#    Routes registered with #protect are gated. All other paths pass through.
#    Per-route :amount_sats overrides the global default.
# ---------------------------------------------------------------------------
app = BSV::X402::Middleware.new(inner_app) do |x402|
  x402.protect '/api/premium',     amount_sats: 100   # 100 satoshis
  x402.protect '/api/data/*',      amount_sats: 50    # 50 sats for any /api/data/ sub-path
  x402.protect '/api/expensive',   amount_sats: 1_000 # premium endpoint
  # /health and all other paths are unprotected.
end

# ---------------------------------------------------------------------------
# 6. Expose the Rack app (used by rackup / Rack::Handler).
# ---------------------------------------------------------------------------
run app
