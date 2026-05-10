# frozen_string_literal: true

# Integration tests that hit the real WhatsOnChain API.
#
# Gated on BSV_INTEGRATION env var to avoid rate-limit failures when
# multiple CI matrix jobs hit WoC simultaneously. CI sets this on a
# single Ruby version (3.4).
#
# Run locally: BSV_INTEGRATION=true bundle exec rspec --tag integration
#
# These tests use well-known, immutable BSV reference data so assertions
# are stable across runs. They prove the SDK can process real WoC responses
# end-to-end — the unit specs with fake fixtures test parsing logic, these
# test the actual API contract.

RSpec.describe 'WoCREST integration', :integration do # rubocop:disable RSpec/DescribeClass
  subject(:protocol) do
    BSV::Network::Protocols::WoCREST.new(
      base_url: 'https://api.whatsonchain.com/v1/bsv/{network}',
      network: :main
    )
  end

  # -- Well-known reference data -------------------------------------------------

  # Genesis block (height 0)
  let(:genesis_hash) { '000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f' }

  # Genesis coinbase tx — contains "The Times 03/Jan/2009 Chancellor on brink
  # of second bailout for banks"
  let(:genesis_txid) { '4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b' }

  # First block mined after the BSV fork (2018-11-15)
  let(:fork_block_height) { 556_767 }
  let(:fork_block_hash) { '000000000000000001d956714215d96ffc00e0afda4cd0a96c96f8d802b1662b' }

  # First 17KB OP_RETURN — Through the Looking-Glass by Lewis Carroll
  let(:opreturn_txid) { '21a5c896f23bea81ae5018dfeb8801ddc68691d0186a7e2d8c011e65e0a396d9' }

  # Test address with a known UTXO (1,000,000 sats at block 948120)
  let(:test_address) { '1AzDmXHX891VQovic5A7iqrW3AnikSf6tm' }
  let(:test_script_hash) { '2673c96e7c5ab126b5f99251882d74c84997a52df85ae6c8ddbd843a7d322ad1' }
  let(:test_utxo_txid) { 'c9995d65d0bc5d3e85c5db33ccef1ead1646d6838868b1afbd7eba18e870e636' }

  # Satoshi's address (genesis coinbase, provably unspendable)
  let(:satoshi_address) { '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa' }

  # A known confirmed tx for merkle proof testing (block 948120)
  let(:confirmed_txid) { test_utxo_txid }

  # ---------------------------------------------------------------------------
  # Health
  # ---------------------------------------------------------------------------

  it 'health returns Whats On Chain' do
    result = protocol.call(:health)

    expect(result).to be_http_success
    expect(result.data).to include('Whats On Chain')
  end

  # ---------------------------------------------------------------------------
  # Chain
  # ---------------------------------------------------------------------------

  it 'current_height returns a positive integer' do
    result = protocol.call(:current_height)

    expect(result).to be_http_success
    expect(result.data).to be_a(Integer)
    expect(result.data).to be > 900_000
  end

  it 'get_chain_info returns chain details' do
    result = protocol.call(:get_chain_info)

    expect(result).to be_http_success
    expect(result.data['chain']).to eq('main')
    expect(result.data['blocks']).to be_a(Integer)
  end

  it 'get_block_header returns the genesis block header' do
    result = protocol.call(:get_block_header, 0)

    expect(result).to be_http_success
    expect(result.data['hash']).to eq(genesis_hash)
    expect(result.data['height']).to eq(0)
    expect(result.data['previousblockhash']).to eq('')
  end

  it 'get_block_headers returns an array of recent headers' do
    result = protocol.call(:get_block_headers)

    expect(result).to be_http_success
    expect(result.data).to be_an(Array)
    expect(result.data.first).to have_key('hash')
    expect(result.data.first).to have_key('height')
  end

  it 'get_circulating_supply returns a numeric string' do
    result = protocol.call(:get_circulating_supply)

    expect(result).to be_http_success
    expect(Float(result.data)).to be > 19_000_000
  end

  # ---------------------------------------------------------------------------
  # Transaction
  # ---------------------------------------------------------------------------

  it 'get_tx returns raw hex for the genesis coinbase' do
    result = protocol.call(:get_tx, genesis_txid)

    expect(result).to be_http_success
    expect(result.data).to be_a(String)
    # The coinbase contains "The Times 03/Jan/2009..."
    expect(result.data).to include('5468652054696d65732030332f4a616e2f32303039')
  end

  it 'get_tx_details returns parsed transaction JSON' do
    result = protocol.call(:get_tx_details, genesis_txid)

    expect(result).to be_http_success
    expect(result.data['txid']).to eq(genesis_txid)
    expect(result.data['blockhash']).to eq(genesis_hash)
    expect(result.data['vout']).to be_an(Array)
  end

  it 'get_output_script returns the genesis coinbase output script' do
    result = protocol.call(:get_output_script, genesis_txid, 0)

    expect(result).to be_http_success
    expect(result.data).to be_a(String)
    # P2PK script ending in OP_CHECKSIG (ac)
    expect(result.data).to end_with('ac')
  end

  it 'get_opreturn returns OP_RETURN data as an array' do
    result = protocol.call(:get_opreturn, opreturn_txid)

    expect(result).to be_http_success
    expect(result.data).to be_an(Array)
    expect(result.data.first).to have_key('hex')
  end

  it 'get_merkle_path returns a TSC proof array' do
    result = protocol.call(:get_merkle_path, confirmed_txid)

    expect(result).to be_http_success
    expect(result.data).to be_an(Array)
    proof = result.data.first
    expect(proof).to have_key('index')
    expect(proof).to have_key('txOrId')
    expect(proof).to have_key('nodes')
    expect(proof['nodes']).to be_an(Array)
  end

  it 'get_tx_binary returns binary data' do
    result = protocol.call(:get_tx_binary, genesis_txid)

    expect(result).to be_http_success
    expect(result.data).to be_a(String)
  end

  # ---------------------------------------------------------------------------
  # UTXO / spent status
  # ---------------------------------------------------------------------------

  it 'get_utxos returns raw WoC UTXO entries for the test address' do
    result = protocol.call(:get_utxos, test_address)

    expect(result).to be_http_success
    expect(result.data).to be_an(Array)
    expect(result.data).not_to be_empty
    utxo = result.data.first
    expect(utxo).to have_key('value')
    expect(utxo).to have_key('tx_hash')
    expect(utxo).to have_key('tx_pos')
    expect(utxo).to have_key('height')
  end

  it 'get_utxos_all returns raw WoC UTXO entries' do
    result = protocol.call(:get_utxos_all, test_address)

    expect(result).to be_http_success
    expect(result.data).to be_an(Array)
    expect(result.data.first).to have_key('value') unless result.data.empty?
  end

  it 'is_utxo returns true for a known unspent output' do
    # vout 1 of test_utxo_txid is the unspent 1M sat output
    result = protocol.call(:is_utxo, test_utxo_txid, 1)

    expect(result).to be_http_success
    expect(result.data).to be(true)
  end

  it 'is_utxo returns false for a known spent output' do
    # vout 0 of test_utxo_txid is spent
    result = protocol.call(:is_utxo, test_utxo_txid, 0)

    expect(result).to be_http_success
    expect(result.data).to be(false)
  end

  it 'is_utxo_bulk returns spent status for multiple outpoints' do
    result = protocol.call(:is_utxo_bulk, [
                             { txid: test_utxo_txid, vout: 0 },
                             { txid: test_utxo_txid, vout: 1 }
                           ])

    expect(result).to be_http_success
    expect(result.data["#{test_utxo_txid}.0"]).to be(false) # spent
    expect(result.data["#{test_utxo_txid}.1"]).to be(true)  # unspent
  end

  it 'valid_root validates the genesis block merkle root' do
    genesis_merkle_root = '4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b'
    result = protocol.call(:valid_root, genesis_merkle_root, 0)

    expect(result).to be_http_success
    expect(result.data).to be(true)
  end

  # ---------------------------------------------------------------------------
  # Script
  # ---------------------------------------------------------------------------

  it 'get_script_unspent returns UTXOs for a known script hash' do
    result = protocol.call(:get_script_unspent, test_script_hash)

    expect(result).to be_http_success
    expect(result.data).to be_an(Array)
  end

  it 'get_script_history returns history for a known script hash' do
    result = protocol.call(:get_script_history, test_script_hash)

    expect(result).to be_http_success
    expect(result.data).to be_an(Array)
    expect(result.data.first).to have_key('tx_hash') unless result.data.empty?
  end

  it 'get_script_all_unspent returns UTXOs for a known script hash' do
    result = protocol.call(:get_script_all_unspent, test_script_hash)

    expect(result).to be_http_success
    expect(result.data).to be_an(Array)
  end

  # ---------------------------------------------------------------------------
  # Address balance / history
  # ---------------------------------------------------------------------------

  it 'get_balance returns a confirmed balance for the test address' do
    result = protocol.call(:get_balance, test_address)

    expect(result).to be_http_success
    expect(result.data['confirmed']).to be_a(Integer)
    expect(result.data['confirmed']).to eq(1_000_000)
  end

  it 'get_unconfirmed_balance returns an unconfirmed balance' do
    result = protocol.call(:get_unconfirmed_balance, test_address)

    expect(result).to be_http_success
    expect(result.data).to have_key('unconfirmed')
  end

  it 'get_history returns transaction history' do
    result = protocol.call(:get_history, test_address)

    expect(result).to be_http_success
    expect(result.data).to be_an(Array)
    expect(result.data.first).to have_key('tx_hash') unless result.data.empty?
  end

  it 'is_address_used returns true for a known used address' do
    result = protocol.call(:is_address_used, test_address)

    expect(result).to be_http_success
    expect(result.data).to be(true)
  end

  # ---------------------------------------------------------------------------
  # Exchange rate / fees / mempool
  # ---------------------------------------------------------------------------

  it 'get_exchange_rate returns a rate' do
    result = protocol.call(:get_exchange_rate)

    expect(result).to be_http_success
    expect(result.data['rate']).to be_a(Numeric)
    expect(result.data['currency']).to eq('USD')
  end

  it 'get_fee_recommendation returns fee info' do
    result = protocol.call(:get_fee_recommendation)

    expect(result).to be_http_success
    expect(result.data['fee']).to be_a(Integer)
    expect(result.data['fee_unit']).to eq('sat/KB')
  end

  it 'get_mempool_info returns mempool stats' do
    result = protocol.call(:get_mempool_info)

    expect(result).to be_http_success
    expect(result.data['size']).to be_a(Integer)
  end
end
