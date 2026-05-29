# frozen_string_literal: true

# Integration tests that hit the live TAAL ARC API.
#
# Required: TAAL_API_KEY — TAAL ARC requires Bearer authentication on every
# endpoint, including /v1/health and /v1/policy. The spec skips cleanly when
# the env var is absent so CI stays green without credentials.
#
# Also gated on BSV_INTEGRATION env var to avoid hitting the live API during
# regular CI runs.
#
# Run locally: BSV_INTEGRATION=true TAAL_API_KEY=... bundle exec rspec --tag integration
#
# Exercises read-only endpoints only:
#   - /v1/health
#   - /v1/policy
#   - /v1/tx/{txid}  (404 behaviour — ARC does not retain historical tx data)
#
# Broadcast tests live in broadcast_integration_spec.rb and require a funded WIF.

RSpec.describe 'ARC integration', :integration do # rubocop:disable RSpec/DescribeClass
  subject(:protocol) do
    BSV::Network::Protocols::ARC.new(
      base_url: 'https://arc.taal.com',
      auth: { bearer: api_key }
    )
  end

  let(:api_key) { ENV.fetch('TAAL_API_KEY', nil) }
  # Genesis coinbase txid — ARC does not retain historical tx status,
  # so any well-known txid is sufficient to trigger a 404 response.
  let(:genesis_txid) { '4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b' }

  before { skip 'set TAAL_API_KEY to run' unless api_key }

  # ---------------------------------------------------------------------------
  # Health
  # ---------------------------------------------------------------------------

  it 'health returns a healthy status' do
    result = protocol.call(:health)

    expect(result).to be_http_success
    expect(result.data['healthy']).to be(true)
  end

  # ---------------------------------------------------------------------------
  # Policy
  # ---------------------------------------------------------------------------

  it 'get_policy returns a valid mining policy' do
    result = protocol.call(:get_policy)

    expect(result).to be_http_success
    expect(result.data).to have_key('policy')
    policy = result.data['policy']
    expect(policy).to be_a(Hash)
    expect(policy['maxscriptsizepolicy']).to be_a(Integer)
    expect(policy['maxscriptsizepolicy']).to be_positive
    expect(policy['miningFee']).to be_a(Hash)
    expect(policy['miningFee']).to have_key('bytes')
    expect(policy['miningFee']).to have_key('satoshis')
  end

  # ---------------------------------------------------------------------------
  # Transaction status — 404 behaviour
  # ---------------------------------------------------------------------------

  it 'get_tx_status returns not_found for a historical txid not retained by ARC' do
    result = protocol.call(:get_tx_status, genesis_txid)

    expect(result).to be_http_not_found
  end
end
