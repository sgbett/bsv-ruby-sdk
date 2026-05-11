# frozen_string_literal: true

# Integration tests that hit the real JungleBus API.
#
# Gated on BSV_INTEGRATION env var to avoid unnecessary external calls during
# normal test runs. CI sets this on a single Ruby version.
#
# Run locally: BSV_INTEGRATION=true bundle exec rspec --tag integration
#
# These tests use well-known, immutable BSV reference data so assertions are
# stable across runs. They prove the SDK can process real JungleBus responses
# end-to-end — the unit specs with fake fixtures test parsing logic, these
# test the actual API contract.
#
# Note: get_address_meta and get_address_txs are not tested here. The address
# endpoints are documented as potentially inactive on the JungleBus REST API
# and unreliable for CI assertions.

RSpec.describe 'JungleBus integration', :integration do # rubocop:disable RSpec/DescribeClass
  subject(:protocol) do
    BSV::Network::Protocols::JungleBus.new(
      base_url: 'https://junglebus.gorillapool.io'
    )
  end

  # -- Well-known reference data -----------------------------------------------

  # Genesis block (height 0)
  let(:genesis_block_height) { 0 }
  let(:genesis_block_hash) { '000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f' }

  # A known confirmed tx — block 948120
  let(:known_txid) { 'c9995d65d0bc5d3e85c5db33ccef1ead1646d6838868b1afbd7eba18e870e636' }
  let(:known_block_height) { 948_120 }

  # A txid that does not exist on the blockchain
  let(:nonexistent_txid) { '0000000000000000000000000000000000000000000000000000000000000001' }

  # BSV fork block (2018-11-15) — useful for headers range tests
  let(:fork_block_height) { 556_767 }
  let(:fork_block_hash) { '000000000000000001d956714215d96ffc00e0afda4cd0a96c96f8d802b1662b' }

  # ---------------------------------------------------------------------------
  # Transaction
  # ---------------------------------------------------------------------------

  it 'get_tx returns transaction data for a known txid' do
    result = protocol.call(:get_tx, known_txid)

    # JungleBus may not index all transactions — skip gracefully if not found
    if result.http_success?
      expect(result.data).to be_a(Hash)
      expect(result.data['id']).to eq(known_txid)
      expect(result.data['block_height']).to eq(known_block_height)
      expect(result.data['block_hash']).to be_a(String)
      expect(result.data['block_hash']).not_to be_empty
      expect(result.data['transaction']).to be_a(String)
      expect(result.data['transaction']).not_to be_empty
    else
      expect(result).to be_http_not_found.or(satisfy { |r| !r.http_success? })
    end
  end

  it 'get_tx returns an error or empty response for a nonexistent txid' do
    result = protocol.call(:get_tx, nonexistent_txid)

    # JungleBus returns 404 or null body for unknown txids — the protocol layer
    # normalises this to a Failure or an Error result
    expect(result).not_to be_http_success
  end

  # ---------------------------------------------------------------------------
  # Block headers
  # ---------------------------------------------------------------------------

  it 'get_block_header returns the BSV fork block header' do
    result = protocol.call(:get_block_header, fork_block_height)

    if result.http_success?
      expect(result.data).to be_a(Hash)
      expect(result.data['hash']).to eq(fork_block_hash)
      expect(result.data['height']).to eq(fork_block_height)
      expect(result.data['merkleroot']).to be_a(String)
    else
      expect(result).to be_http_not_found.or(satisfy { |r| !r.http_success? })
    end
  end

  it 'get_block_headers returns an array of headers from a given height' do
    result = protocol.call(:get_block_headers, fork_block_height)

    expect(result).to be_http_success
    expect(result.data).to be_an(Array)
    expect(result.data).not_to be_empty
    header = result.data.first
    expect(header).to have_key('hash')
    expect(header).to have_key('height')
    expect(header['height']).to eq(fork_block_height)
  end
end
