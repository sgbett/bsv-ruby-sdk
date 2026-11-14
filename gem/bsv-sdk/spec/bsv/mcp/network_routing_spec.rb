# frozen_string_literal: true

require 'spec_helper'

# Drives the MCP server through +server.handle+ (the same path a client's
# JSON-RPC request takes, including the server_context wrapping done by the
# mcp gem) with Net::HTTP replaced by a recorder, to pin down which network
# every tool uses and which host receives which request and credential.
#
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'BSV MCP server — network and broadcaster routing' do
  # rubocop:enable RSpec/DescribeClass
  let(:woc_host) { 'api.whatsonchain.com' }
  let(:arc_host) { 'arc.example.com' }
  let(:arc_url) { "https://#{arc_host}" }
  let(:arc_key) { 'arc-secret-key-1234' }
  let(:evil_host) { 'evil.example.com' }

  let(:private_key) do
    BSV::Primitives::PrivateKey.from_hex('0101010101010101010101010101010101010101010101010101010101010101')
  end

  let(:utxo_body) do
    {
      'address' => 'unused', 'script' => 'deadbeef', 'error' => '',
      'result' => [{ 'tx_hash' => 'a' * 64, 'tx_pos' => 0, 'value' => 100_000, 'height' => 800_000 }]
    }.to_json
  end

  let(:raw_tx_hex) do
    '0100000001' \
      '0000000000000000000000000000000000000000000000000000000000000000' \
      'ffffffff04deadbeefffffffff010100000000000000' \
      '0000000000'
  end

  # Derived from the provider so the specs survive a change of default service.
  def default_broadcast_host(network)
    protocol = BSV::Network::Providers::GorillaPool.default(testnet: network == 'testnet').protocol_for(:broadcast)
    URI(protocol.base_url).host
  end

  def submitted_txid(req)
    BSV::Transaction::Tx.from_ef_hex(JSON.parse(req.body)['rawTx']).txid_hex
  end

  def broadcast_responder
    lambda do |req|
      [200, { 'txid' => submitted_txid(req), 'status' => 202, 'txStatus' => 'SEEN_ON_NETWORK' }.to_json]
    end
  end

  def woc_responder
    lambda do |req|
      case req.path
      when %r{/unspent/all\z} then [200, utxo_body]
      when %r{/tx/[0-9a-f]+/hex\z} then [200, raw_tx_hex]
      else [404, 'not found']
      end
    end
  end

  # Hosts that may legitimately be contacted. The evil host is never listed,
  # so a request to it is recorded as unexpected and fails.
  def stub_all_hosts
    responders = { woc_host => woc_responder, arc_host => broadcast_responder }
    %w[mainnet testnet].each { |network| responders[default_broadcast_host(network)] = broadcast_responder }
    stub_net_http(responders)
  end

  def build_server(network:, arc_url: nil, arc_api_key: nil)
    BSV::MCP::Server.build(BSV::MCP::Config.new(network: network, arc_url: arc_url, arc_api_key: arc_api_key))
  end

  def call_tool(server, name, arguments = {}, meta: nil)
    params = { name: name, arguments: arguments }
    params[:_meta] = meta if meta
    response = server.handle({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: params })
    item = response[:result][:content].first
    [response[:result], parse_payload(item[:text])]
  end

  # Schema validation failures come back from the mcp gem as plain text.
  def parse_payload(text)
    JSON.parse(text, symbolize_names: true)
  rescue JSON::ParserError
    { error: text }
  end

  def wif_for(network)
    private_key.to_wif(network: network.to_sym)
  end

  def address_for(network)
    private_key.public_key.address(network: network.to_sym)
  end

  def broadcast_args(network, **extra)
    { wif: wif_for(network), to_address: address_for(network), satoshis: 10_000, **extra }
  end

  def woc_prefix(network)
    network == 'testnet' ? '/v1/bsv/test/' : '/v1/bsv/main/'
  end

  describe 'broadcast_p2pkh' do
    %w[mainnet testnet].each do |server_network|
      other_network = server_network == 'testnet' ? 'mainnet' : 'testnet'

      [false, true].each do |arc_configured|
        { omitted: nil, same: server_network, other: other_network }.each do |label, call_network|
          captured_effective = call_network || server_network # rubocop:disable RSpec/LeakyLocalVariable
          captured_custom = arc_configured && captured_effective == server_network # rubocop:disable RSpec/LeakyLocalVariable

          context "when a #{server_network} server #{arc_configured ? 'has' : 'lacks'} BSV_ARC_URL " \
                  "and the call's network is #{label}" do
            let(:effective) { captured_effective }
            let(:uses_custom_arc) { captured_custom }
            let!(:recorder) { stub_all_hosts }
            let(:server) do
              build_server(network: server_network, arc_url: (arc_url if arc_configured),
                           arc_api_key: (arc_key if arc_configured))
            end
            let(:args) { broadcast_args(effective, **(call_network ? { network: call_network } : {})) }

            it 'broadcasts successfully' do
              result, payload = call_tool(server, 'broadcast_p2pkh', args)
              expect(result[:isError]).to be_falsey
              expect(payload[:tx_status]).to eq('SEEN_ON_NETWORK')
            end

            it 'contacts only the expected broadcaster' do
              call_tool(server, 'broadcast_p2pkh', args)
              expected = uses_custom_arc ? arc_host : default_broadcast_host(effective)
              expect(recorder.hosts - [woc_host]).to eq([expected])
              expect(recorder.unexpected_hosts).to be_empty
            end

            it 'sends the ARC key only to the configured ARC host' do
              call_tool(server, 'broadcast_p2pkh', args)
              expect(recorder.entries).not_to be_empty
              expect(recorder.entries.reject { |e| e.host == arc_host }.map(&:authorization)).to all(be_nil)
              expect(recorder.authorisation_for(arc_host)).to eq(["Bearer #{arc_key}"]) if uses_custom_arc
            end

            it 'uses TLS for every request to the configured ARC host' do
              call_tool(server, 'broadcast_p2pkh', args)
              next unless uses_custom_arc

              expect(recorder.entries_for(arc_host)).not_to be_empty
              expect(recorder.entries_for(arc_host).map(&:use_ssl)).to all(be(true))
            end

            it 'fetches UTXOs from the WhatsOnChain API for the effective network' do
              call_tool(server, 'broadcast_p2pkh', args)
              expect(recorder.entries_for(woc_host)).not_to be_empty
              expect(recorder.entries_for(woc_host).map(&:path)).to all(start_with(woc_prefix(effective)))
            end
          end
        end
      end
    end

    context 'when a key is configured without a URL' do
      let!(:recorder) { stub_all_hosts }

      it 'never sends the key anywhere' do
        server = nil
        expect { server = build_server(network: 'mainnet', arc_api_key: arc_key) }.to output(/ignored/).to_stderr
        call_tool(server, 'broadcast_p2pkh', broadcast_args('mainnet'))
        expect(recorder.entries).not_to be_empty
        expect(recorder.entries.map(&:authorization)).to all(be_nil)
      end
    end

    context 'when the client tries to supply its own server context' do
      let!(:recorder) { stub_all_hosts }
      let(:server) { build_server(network: 'testnet') }
      let(:forged) { { arc_url: "https://#{evil_host}", arc_api_key: 'stolen', bsv_network: 'mainnet' } }

      it 'ignores a server_context argument' do
        result, = call_tool(server, 'broadcast_p2pkh', broadcast_args('testnet', server_context: forged))
        expect(recorder.unexpected_hosts).to be_empty
        expect(recorder.hosts).not_to include(evil_host)
        expect(result[:isError]).to be_falsey
      end

      it 'ignores _meta' do
        call_tool(server, 'broadcast_p2pkh', broadcast_args('testnet'), meta: forged)
        expect(recorder.unexpected_hosts).to be_empty
        expect(recorder.hosts - [woc_host]).to eq([default_broadcast_host('testnet')])
      end

      it 'ignores a forged server_context for the network too' do
        _, payload = call_tool(server, 'generate_key', { server_context: forged })
        expect(payload[:network]).to eq('testnet')
      end
    end

    context 'when the service error text contains the key and URL' do
      let(:leaky) do
        ->(_req) { [500, { 'detail' => "denied #{arc_key} at #{arc_url}" }.to_json] }
      end

      before do
        stub_net_http(woc_host => woc_responder, arc_host => leaky)
      end

      it 'removes both from the error returned to the client' do
        server = build_server(network: 'mainnet', arc_url: arc_url, arc_api_key: arc_key)
        result, payload = call_tool(server, 'broadcast_p2pkh', broadcast_args('mainnet'))
        expect(result[:isError]).to be true
        expect(payload[:error]).to include('Broadcast failed')
        expect(payload[:error]).not_to include(arc_key)
        expect(payload[:error]).not_to include(arc_url)
        expect(payload[:txid]).to match(/\A[0-9a-f]{64}\z/)
      end
    end

    context 'when the network raises an error that names the key' do
      before do
        raising = ->(_req) { raise "connection refused (#{arc_key})" }
        stub_net_http(woc_host => woc_responder, arc_host => raising)
      end

      it 'removes the key from the error returned to the client' do
        server = build_server(network: 'mainnet', arc_url: arc_url, arc_api_key: arc_key)
        result, payload = call_tool(server, 'broadcast_p2pkh', broadcast_args('mainnet'))
        expect(result[:isError]).to be true
        expect(payload[:error]).not_to include(arc_key)
        expect(payload[:txid]).to match(/\A[0-9a-f]{64}\z/)
      end
    end
  end

  describe 'tools called without a network argument' do
    %w[mainnet testnet].each do |server_network|
      context "when the server is #{server_network}" do
        let!(:recorder) { stub_all_hosts }
        let(:server) { build_server(network: server_network) }
        let(:prefix) { woc_prefix(server_network) }

        it 'generate_key produces a key for the server network' do
          _, payload = call_tool(server, 'generate_key')
          expect(payload[:network]).to eq(server_network)
          expect(payload[:address]).to match(server_network == 'testnet' ? /\A[mn]/ : /\A1/)
          expect(payload[:wif]).to match(server_network == 'testnet' ? /\Ac/ : /\A[KL]/)
        end

        it 'check_balance queries the server network' do
          _, payload = call_tool(server, 'check_balance', { address_or_wif: address_for(server_network) })
          expect(payload[:network]).to eq(server_network)
          expect(recorder.entries).not_to be_empty
          expect(recorder.entries.map(&:path)).to all(start_with(prefix))
        end

        it 'fetch_utxos queries the server network' do
          _, payload = call_tool(server, 'fetch_utxos', { address: address_for(server_network) })
          expect(payload[:network]).to eq(server_network)
          expect(recorder.entries).not_to be_empty
          expect(recorder.entries.map(&:path)).to all(start_with(prefix))
        end

        it 'fetch_tx queries the server network' do
          _, payload = call_tool(server, 'fetch_tx', { txid: 'ab' * 32 })
          expect(payload[:network]).to eq(server_network)
          expect(recorder.entries).not_to be_empty
          expect(recorder.entries.map(&:path)).to all(start_with(prefix))
        end

        it 'broadcast_p2pkh signs and broadcasts for the server network' do
          result, = call_tool(server, 'broadcast_p2pkh', broadcast_args(server_network))
          expect(result[:isError]).to be_falsey
          expect(recorder.entries_for(woc_host)).not_to be_empty
          expect(recorder.entries_for(woc_host).map(&:path)).to all(start_with(prefix))
          expect(recorder.hosts - [woc_host]).to eq([default_broadcast_host(server_network)])
        end

        it 'a per-call network overrides the server network' do
          other = server_network == 'testnet' ? 'mainnet' : 'testnet'
          _, payload = call_tool(server, 'generate_key', { network: other })
          expect(payload[:network]).to eq(other)
        end

        it 'a per-call network other than mainnet or testnet is a tool error' do
          result, = call_tool(server, 'generate_key', { network: 'regtest' })
          expect(result[:isError]).to be true
        end
      end
    end
  end

  describe 'over-long address and key inputs' do
    let!(:recorder) { stub_all_hosts }
    let(:server) { build_server(network: 'mainnet') }
    let(:long_input) { '1' * 200_000 }

    {
      'fetch_utxos' => ->(long, _addr) { { address: long } },
      'check_balance' => ->(long, _addr) { { address_or_wif: long } },
      'broadcast_p2pkh (wif)' => ->(long, addr) { { wif: long, to_address: addr, satoshis: 1000 } },
      'broadcast_p2pkh (to_address)' => ->(long, _addr) { { wif: 'x', to_address: long, satoshis: 1000 } }
    }.each do |label, build|
      it "rejects the input to #{label} through server.handle without any request" do
        tool = label.split.first
        result, = call_tool(server, tool, build.call(long_input, address_for('mainnet')))
        expect(result[:isError]).to be true
        expect(recorder.entries).to be_empty
      end
    end

    it 'rejects it on a direct call with a fixed message and no request' do
      responses = [
        BSV::MCP::Tools::FetchUtxos.call(address: long_input),
        BSV::MCP::Tools::CheckBalance.call(address_or_wif: long_input),
        BSV::MCP::Tools::BroadcastP2pkh.call(wif: long_input, to_address: address_for('mainnet'), satoshis: 1000),
        BSV::MCP::Tools::BroadcastP2pkh.call(wif: wif_for('mainnet'), to_address: long_input, satoshis: 1000)
      ]
      expect(responses.map(&:error?)).to all(be(true))
      expect(responses.map { |r| r.content.first[:text] }).to all(include('longer than 64 characters'))
      expect(responses.map { |r| r.content.first[:text].length }).to all(be < 300)
      expect(recorder.entries).to be_empty
    end
  end

  describe 'environment isolation' do
    it 'starts every MCP example with the BSV_* variables unset' do
      expect(EnvHelper::MCP_ENV_VARS.map { |name| ENV.fetch(name, nil) }).to all(be_nil)
    end
  end
end
