# frozen_string_literal: true

# Integration tests that hit the real JungleBus API.
#
# Gated on BSV_INTEGRATION env var.
# Run locally: BSV_INTEGRATION=true bundle exec rspec --tag integration

RSpec.describe 'JungleBus integration', :integration do # rubocop:disable RSpec/DescribeClass
  subject(:protocol) do
    BSV::Network::Protocols::JungleBus.new(
      base_url: 'https://junglebus.gorillapool.io'
    )
  end

  # First BSV block after the fork
  let(:fork_block_height) { 556_767 }
  let(:fork_block_hash) { '000000000000000001d956714215d96ffc00e0afda4cd0a96c96f8d802b1662b' }

  # Test address (ALICE CI wallet)
  let(:test_address) { '1AzDmXHX891VQovic5A7iqrW3AnikSf6tm' }
  let(:test_utxo_txid) { 'c9995d65d0bc5d3e85c5db33ccef1ead1646d6838868b1afbd7eba18e870e636' }

  # ---------------------------------------------------------------------------
  # Transaction
  # ---------------------------------------------------------------------------

  it 'get_tx returns transaction data with base64-encoded tx' do
    result = protocol.call(:get_tx, test_utxo_txid)

    expect(result).to be_a(BSV::Network::Result::Success)
    expect(result.data['id']).to eq(test_utxo_txid)
    expect(result.data['transaction']).to be_a(String)
    expect(result.data['block_height']).to eq(948_120)
    expect(result.data['block_index']).to be_a(Integer)
    expect(result.data['output_types']).to be_an(Array)
  end

  # ---------------------------------------------------------------------------
  # Address
  # ---------------------------------------------------------------------------

  it 'get_address_meta returns transaction metadata for the test address' do
    result = protocol.call(:get_address_meta, test_address)

    expect(result).to be_a(BSV::Network::Result::Success)
    expect(result.data).to be_an(Array)
    expect(result.data).not_to be_empty
    expect(result.data.first).to have_key('transaction_id')
    expect(result.data.first).to have_key('block_height')
  end

  it 'get_address_txs returns empty body (endpoint appears inactive on REST API)' do
    # This endpoint returns 200 with zero bytes for all addresses.
    # It may require a JungleBus subscription to populate.
    result = protocol.call(:get_address_txs, test_address)

    expect(result).to be_a(BSV::Network::Result::Error)
    expect(result.message).to include('JSON/response error')
  end

  # ---------------------------------------------------------------------------
  # Block headers
  # ---------------------------------------------------------------------------

  it 'get_block_header returns the first BSV fork block header' do
    result = protocol.call(:get_block_header, fork_block_height)

    expect(result).to be_a(BSV::Network::Result::Success)
    expect(result.data['hash']).to eq(fork_block_hash)
    expect(result.data['height']).to eq(fork_block_height)
    expect(result.data['merkleroot']).to be_a(String)
  end

  it 'get_block_headers returns an array of headers from a height' do
    result = protocol.call(:get_block_headers, fork_block_height)

    expect(result).to be_a(BSV::Network::Result::Success)
    expect(result.data).to be_an(Array)
    expect(result.data).not_to be_empty
    expect(result.data.first['height']).to eq(fork_block_height)
  end
end
