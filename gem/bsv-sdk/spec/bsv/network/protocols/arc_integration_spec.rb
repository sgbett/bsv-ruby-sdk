# frozen_string_literal: true

# Integration tests that hit the live TAAL ARC API.
#
# Gated on BSV_INTEGRATION env var to avoid hitting the live API during
# regular CI runs.
#
# Run locally: BSV_INTEGRATION=true bundle exec rspec --tag integration
#
# These tests exercise only read-only, authentication-free endpoints:
#   - /v1/health
#   - /v1/policy
#   - /v1/tx/{txid}  (404 behaviour — ARC does not retain historical tx data)
#
# Broadcast tests are omitted: they require a valid signed transaction and
# would have real network side effects.

RSpec.describe 'ARC integration', :integration do # rubocop:disable RSpec/DescribeClass
  subject(:protocol) do
    BSV::Network::Protocols::ARC.new(
      base_url: 'https://arc.taal.com'
    )
  end

  # Genesis coinbase txid — ARC does not retain historical tx status,
  # so any well-known txid is sufficient to trigger a 404 response.
  let(:genesis_txid) { '4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b' }

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
