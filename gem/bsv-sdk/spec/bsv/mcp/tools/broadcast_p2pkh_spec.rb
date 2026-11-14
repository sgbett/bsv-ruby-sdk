# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'BSV::MCP::Tools::BroadcastP2pkh' do
  subject(:tool) { BSV::MCP::Tools::BroadcastP2pkh }

  # A deterministic private key for reproducible tests (hex of 1..32)
  let(:private_key) do
    BSV::Primitives::PrivateKey.from_hex('0101010101010101010101010101010101010101010101010101010101010101')
  end
  let(:sender_address) { private_key.public_key.address(network: :mainnet) }
  let(:wif) { private_key.to_wif }

  let(:recipient_address) { '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa' }

  let(:broadcaster_http_class) { Class.new(mock_http_class) }

  # A funded UTXO worth 100_000 satoshis
  let(:utxo_response_body) do
    {
      'address' => '1test',
      'script' => 'deadbeef',
      'result' => [
        {
          'tx_hash' => 'a' * 64,
          'tx_pos' => 0,
          'value' => 100_000,
          'height' => 800_000
        }
      ],
      'error' => ''
    }.to_json
  end

  let(:mock_http_class) do
    Class.new do
      include FakeHttpResponse

      def initialize(code, body)
        @code = code
        @body = body
      end

      # URIs requested through this client, so specs can assert which
      # network and host a tool really talked to.
      def self.requested
        @requested ||= []
      end

      def request(uri, req)
        self.class.requested << uri.to_s
        body = @body.respond_to?(:call) ? @body.call(req) : @body
        fake_http_response(@code, body)
      end
    end
  end

  # The txid of the transaction a broadcast request carries (the tool
  # submits Extended Format hex).
  def submitted_txid(req)
    BSV::Transaction::Tx.from_ef_hex(JSON.parse(req.body)['rawTx']).txid_hex
  end

  # The broadcast services answer {txid, status: 202, txStatus}.
  def broadcast_reply(tx_status, **overrides)
    lambda do |req|
      { 'txid' => submitted_txid(req), 'status' => 202, 'txStatus' => tx_status }.merge(overrides.transform_keys(&:to_s)).to_json
    end
  end

  # Inject the fake HTTP client but keep the network the tool asked for, so
  # the requested URIs show which network was really used.
  def stub_woc(code, body)
    http = mock_http_class.new(code, body)
    allow(BSV::Network::Providers::WhatsOnChain).to receive(:default).and_wrap_original do |original, **opts|
      original.call(**opts, http_client: http)
    end
  end

  def stub_broadcaster(code, body)
    http = broadcaster_http_class.new(code, body)
    allow(BSV::Network::Providers::GorillaPool).to receive(:default).and_wrap_original do |original, **opts|
      original.call(**opts, http_client: http)
    end
  end

  def call_tool(**opts)
    response = tool.call(wif: wif, to_address: recipient_address, satoshis: 10_000, **opts)
    [response, JSON.parse(response.content.first[:text], symbolize_names: true)]
  end

  describe '.call with sufficient funds' do
    before do
      stub_woc(200, utxo_response_body)
      stub_broadcaster(200, broadcast_reply('RECEIVED'))
    end

    it 'is a successful MCP::Tool::Response' do
      response, = call_tool
      expect(response).to be_a(MCP::Tool::Response)
      expect(response.error?).to be false
    end

    it 'returns the txid computed from the signed transaction' do
      _, result = call_tool
      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
      expect(BSV::Transaction::Tx.from_hex(result[:hex]).txid_hex).to eq(result[:txid])
    end

    it 'returns the service txStatus, not the HTTP code' do
      _, result = call_tool
      expect(result[:tx_status]).to eq('RECEIVED')
    end

    it 'does not return the retired status or state fields' do
      _, result = call_tool
      expect(result.keys).to contain_exactly(:txid, :tx_status, :hex)
    end

    it 'includes structured_content with txid and tx_status' do
      response, result = call_tool
      expect(response.structured_content).to include(txid: result[:txid], tx_status: 'RECEIVED')
    end
  end

  describe '.call with insufficient funds' do
    before { stub_woc(200, utxo_response_body) }

    it 'returns an error response when requesting more than available' do
      response = tool.call(wif: wif, to_address: recipient_address, satoshis: 200_000)
      expect(response.error?).to be true
    end

    it 'includes an error message mentioning insufficient funds' do
      result = JSON.parse(
        tool.call(wif: wif, to_address: recipient_address, satoshis: 200_000).content.first[:text],
        symbolize_names: true
      )
      expect(result[:error]).to include('Insufficient funds')
    end
  end

  describe '.call with empty UTXO set' do
    before { stub_woc(200, '[]') }

    it 'returns an error response' do
      response = tool.call(wif: wif, to_address: recipient_address, satoshis: 10_000)
      expect(response.error?).to be true
    end

    it 'mentions no UTXOs found' do
      result = JSON.parse(
        tool.call(wif: wif, to_address: recipient_address, satoshis: 10_000).content.first[:text],
        symbolize_names: true
      )
      expect(result[:error]).to include('No UTXOs')
    end
  end

  describe '.call with an invalid WIF key' do
    it 'returns an error response' do
      response = tool.call(wif: 'not-a-valid-wif', to_address: recipient_address, satoshis: 10_000)
      expect(response.error?).to be true
    end

    it 'includes an error message' do
      result = JSON.parse(
        tool.call(wif: 'not-a-valid-wif', to_address: recipient_address, satoshis: 10_000).content.first[:text],
        symbolize_names: true
      )
      expect(result[:error]).to be_a(String)
      expect(result[:error]).not_to be_empty
    end

    # Regression guard for #801: previously only ArgumentError was rescued,
    # so a nil WIF raised NoMethodError out of the tool handler and crashed
    # the MCP server response cycle.
    it 'returns a structured error for nil WIF (not just ArgumentError)' do
      response = tool.call(wif: nil, to_address: recipient_address, satoshis: 10_000)
      expect(response.error?).to be true
    end
  end

  describe '.call when the service rejects the broadcast with an HTTP error' do
    before do
      stub_woc(200, utxo_response_body)
      rejection_body = { 'title' => 'transaction rejected', 'detail' => 'transaction rejected', 'txStatus' => 'REJECTED' }.to_json
      stub_broadcaster(422, rejection_body)
    end

    it 'returns an error response carrying the computed txid' do
      response, result = call_tool
      expect(response.error?).to be true
      expect(result[:error]).to include('Broadcast failed')
      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
    end
  end

  describe '.call when a 2xx reply carries a rejected txStatus' do
    before { stub_woc(200, utxo_response_body) }

    %w[REJECTED DOUBLE_SPEND_ATTEMPTED INVALID MALFORMED MINED_IN_STALE_BLOCK ORPHANED].each do |status|
      it "reports #{status} as an error with the computed txid" do
        stub_broadcaster(200, broadcast_reply(status))
        response, result = call_tool
        expect(response.error?).to be true
        expect(result[:error]).to include(status)
        expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
      end
    end

    it 'reports a lower-case rejection too' do
      stub_broadcaster(200, broadcast_reply('double_spend_attempted'))
      response, = call_tool
      expect(response.error?).to be true
    end
  end

  describe '.call when the reply names a different txid' do
    before do
      stub_woc(200, utxo_response_body)
      stub_broadcaster(200, broadcast_reply('RECEIVED', txid: 'ab' * 32))
    end

    it 'returns an error carrying the computed txid' do
      response, result = call_tool
      expect(response.error?).to be true
      expect(result[:error]).to include('different txid')
      expect(result[:txid]).not_to eq('ab' * 32)
    end
  end

  describe '.call when the reply carries an orphan marker in extraInfo' do
    before do
      stub_woc(200, utxo_response_body)
      stub_broadcaster(200, broadcast_reply('RECEIVED', extraInfo: 'parent is ORPHAN'))
    end

    it 'reports an error with the computed txid' do
      response, result = call_tool
      expect(response.error?).to be true
      expect(result[:error]).to include('rejected')
      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
    end
  end

  describe '.call when txStatus is service-controlled text' do
    before { stub_woc(200, utxo_response_body) }

    it 'omits a status that is not a plain token' do
      stub_broadcaster(200, broadcast_reply('see https://evil.example/?x=1 now'))
      response, result = call_tool
      expect(response.error?).to be false
      expect(result).not_to have_key(:tx_status)
    end

    it 'omits a non-string status' do
      stub_broadcaster(200, broadcast_reply({ 'a' => 1 }))
      _, result = call_tool
      expect(result).not_to have_key(:tx_status)
    end

    it 'omits a status equal to the configured key' do
      stub_broadcaster(200, broadcast_reply('S3CRETKEY'))
      context = { arc_api_key: BSV::MCP::Secret.new('S3CRETKEY') }
      response = tool.call(wif: wif, to_address: recipient_address, satoshis: 10_000, server_context: context)
      expect(response.content.first[:text]).not_to include('S3CRETKEY')
    end
  end

  describe '.call when the reply carries no txid' do
    before do
      stub_woc(200, utxo_response_body)
      stub_broadcaster(200, { 'status' => 202, 'txStatus' => 'RECEIVED' }.to_json)
    end

    it 'still returns the computed txid' do
      response, result = call_tool
      expect(response.error?).to be false
      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
    end
  end

  describe '.call input validation' do
    let(:testnet_wif) { private_key.to_wif(network: :testnet) }
    let(:testnet_address) { private_key.public_key.address(network: :testnet) }
    let(:mainnet_message) { 'to_address is not a P2PKH address for mainnet' }
    let(:testnet_message) { 'to_address is not a P2PKH address for testnet' }
    let(:invalid_wif_message) { 'wif is not a valid WIF private key for mainnet' }

    # Addresses with a valid checksum and the right version byte but a payload
    # of +length+ bytes, so only the payload check can reject them.
    def encoded(version, length)
      BSV::Primitives::Base58.check_encode(version.b + ("\x11".b * length))
    end

    before do
      stub_woc(200, utxo_response_body)
      stub_broadcaster(200, broadcast_reply('RECEIVED'))
    end

    # Asserts the call is refused with exactly +message+, never echoes
    # +echoed+, and never reaches the UTXO lookup.
    def expect_rejection(message, echoed: nil, **opts)
      response, result = call_tool(**opts)
      expect(response.error?).to be true
      expect(result[:error]).to eq(message)
      expect(result[:error]).not_to include(echoed) if echoed
      expect(BSV::Network::Providers::WhatsOnChain).not_to have_received(:default)
    end

    it 'rejects a P2SH recipient' do
      p2sh = encoded("\x05", 10)
      expect(p2sh.length).to eq(20)
      expect_rejection(mainnet_message, to_address: p2sh, echoed: p2sh)
    end

    it 'rejects a testnet recipient on a mainnet call' do
      expect_rejection(mainnet_message, to_address: testnet_address, echoed: testnet_address)
    end

    it 'rejects a mainnet recipient on a testnet call' do
      expect_rejection(testnet_message, wif: testnet_wif, network: 'testnet', echoed: recipient_address)
    end

    it 'rejects a testnet WIF on a mainnet call without echoing it' do
      expect_rejection('WIF private key is not for mainnet', wif: testnet_wif, echoed: testnet_wif)
    end

    {
      'an invalid Base58 character' => ->(key) { "0#{key[1..]}" },
      'a bad checksum' => ->(key) { "#{key[0..-2]}#{key[-1] == '2' ? '3' : '2'}" },
      'a character above U+00FF' => ->(key) { "Ā#{key[1..]}" },
      'a short payload' => ->(_key) { BSV::Primitives::Base58.check_encode("\x80".b + ("\x11".b * 31)) },
      'a long payload' => ->(_key) { BSV::Primitives::Base58.check_encode("\x80".b + ("\x11".b * 33)) }
    }.each do |label, mutate|
      it "returns a fixed message for a WIF with #{label}" do
        input = mutate.call(wif)
        expect_rejection(invalid_wif_message, wif: input, echoed: input)
      end
    end

    it 'echoes no character of a WIF with an invalid Base58 character' do
      _, result = call_tool(wif: "0#{wif[1..]}")
      expect(result[:error]).not_to include('0')
    end

    it 'echoes no character of a WIF with a character above U+00FF' do
      _, result = call_tool(wif: "Ā#{wif[1..]}")
      expect(result[:error]).not_to include(256.chr('UTF-8'))
    end

    it 'returns the fixed message for a nil WIF' do
      expect_rejection(invalid_wif_message, wif: nil)
    end

    it 'rejects a mainnet WIF on a testnet call' do
      expect_rejection('WIF private key is not for testnet', to_address: testnet_address, network: 'testnet')
    end

    it 'rejects a per-call network other than mainnet or testnet' do
      response, result = call_tool(network: 'regtest')
      expect(response.error?).to be true
      expect(result[:error]).to include("'mainnet' or 'testnet'")
    end

    it 'rejects a recipient with a bad checksum' do
      bad = "#{recipient_address[0..-2]}x"
      expect_rejection(mainnet_message, to_address: bad, echoed: bad)
    end

    it 'rejects a 20-character string of ones with a bad checksum' do
      expect_rejection(mainnet_message, to_address: '1' * 20)
    end

    # 17GuhfEA8T1Zvj872QAa is 0x00 plus ten 0x11 bytes, 20 characters, which
    # Script.p2pkh_lock would take as a raw hash of its ASCII bytes.
    %w[17GuhfEA8T1Zvj872QAa 111111111111114xynwY].each do |short_address|
      it "rejects the 20-character short-payload address #{short_address}" do
        expect(short_address.length).to eq(20)
        expect_rejection(mainnet_message, to_address: short_address, echoed: short_address)
      end
    end

    [0, 9, 11, 19, 21, 33].each do |length|
      it "rejects a mainnet recipient with a #{length}-byte payload" do
        address = encoded("\x00", length)
        expect_rejection(mainnet_message, to_address: address, echoed: address)
      end
    end

    [0, 9, 10, 19, 21].each do |length|
      it "rejects a testnet recipient with a #{length}-byte payload" do
        address = encoded("\x6f", length)
        expect_rejection(testnet_message, wif: testnet_wif, network: 'testnet', to_address: address, echoed: address)
      end
    end

    it 'rejects a WIF given as the recipient without echoing it' do
      expect_rejection(mainnet_message, to_address: wif, echoed: wif)
    end

    it 'rejects a paymail recipient' do
      expect_rejection(mainnet_message, to_address: 'alice@example.com')
    end

    it 'rejects a recipient with surrounding whitespace' do
      expect_rejection(mainnet_message, to_address: " #{recipient_address}")
      expect_rejection(mainnet_message, to_address: "#{recipient_address}\n")
    end

    it 'rejects 20 raw binary bytes as the recipient' do
      expect_rejection(mainnet_message, to_address: "\x11".b * 20)
    end

    it 'rejects non-ASCII text as the recipient' do
      expect_rejection(mainnet_message, to_address: 'é' * 10)
    end

    it 'rejects a character above U+00FF in the recipient' do
      expect_rejection(mainnet_message, to_address: "#{recipient_address[0, 19]}Ā")
    end

    [nil, 42, ['1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa']].each do |value|
      it "rejects a #{value.class} recipient" do
        expect_rejection(mainnet_message, to_address: value)
      end
    end
  end

  describe '.call with a valid recipient' do
    let(:recipient_hash_hex) { '62e907b15cbf27d5425399ebf6f0fb50ebb88f18' }
    let(:locked_hashes) { [] }

    before do
      stub_woc(200, utxo_response_body)
      stub_broadcaster(200, broadcast_reply('RECEIVED'))
      seen = locked_hashes
      allow(BSV::Script::Script).to receive(:p2pkh_lock).and_wrap_original do |original, arg|
        seen << arg
        original.call(arg)
      end
    end

    def output_script_hex(result, index)
      BSV::Transaction::Tx.from_hex(result[:hex]).outputs[index].locking_script.to_hex
    end

    it 'locks the payment to the literal hash behind the address' do
      _, result = call_tool
      expect(output_script_hex(result, 0)).to eq("76a914#{recipient_hash_hex}88ac")
    end

    it 'locks the change to the sender key hash, which is the sender address hash' do
      _, result = call_tool
      sender_hash = BSV::Primitives::Base58.check_decode(sender_address)[1..]
      expect(sender_hash).to eq(private_key.public_key.hash160)
      expect(output_script_hex(result, 1)).to eq("76a914#{sender_hash.unpack1('H*')}88ac")
    end

    it 'passes Script.p2pkh_lock a binary hash, never an address string' do
      call_tool
      expect(locked_hashes.map(&:bytesize).uniq).to eq([20])
      expect(locked_hashes.map(&:encoding).uniq).to eq([Encoding::BINARY])
      expect(locked_hashes.map { |hash| hash.unpack1('H*') }).to include(recipient_hash_hex)
    end
  end

  describe '.call with testnet' do
    before do
      stub_woc(200, utxo_response_body)
      stub_broadcaster(200, broadcast_reply('RECEIVED'))
    end

    let(:testnet_key) { BSV::Primitives::PrivateKey.generate }
    let(:testnet_wif) { testnet_key.to_wif(network: :testnet) }
    let(:testnet_recipient) { testnet_key.public_key.address(network: :testnet) }

    it 'uses testnet for WhatsOnChain and Arcade' do
      response = tool.call(wif: testnet_wif, to_address: testnet_recipient, satoshis: 10_000, network: 'testnet')
      result = JSON.parse(response.content.first[:text], symbolize_names: true)
      expect(result[:tx_status]).to eq('RECEIVED')
    end

    it 'talks to the testnet broadcaster and the testnet WhatsOnChain API' do
      tool.call(wif: testnet_wif, to_address: testnet_recipient, satoshis: 10_000, network: 'testnet')
      testnet_host = URI(BSV::Network::Providers::GorillaPool.default(testnet: true).protocol_for(:broadcast).base_url).host
      expect(broadcaster_http_class.requested).not_to be_empty
      expect(broadcaster_http_class.requested).to all(include(testnet_host))
      expect(mock_http_class.requested).not_to be_empty
      expect(mock_http_class.requested).to all(include('/v1/bsv/test/'))
    end
  end
end
