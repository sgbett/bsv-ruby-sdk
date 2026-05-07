# frozen_string_literal: true

require 'spec_helper'

# Protocol-level integration tests for the BSV MCP server.
#
# These tests exercise the full JSON-RPC dispatch path — from a raw request
# hash through `server.handle` to the final response — without starting a
# process or touching the network. Each example simulates what an MCP client
# (such as Claude Code) would send over stdio.
#
# `server.handle` returns the JSON-RPC response hash with the tool's
# `MCP::Content::Text` objects intact in `result[:content]`. Access their
# text payload via `.text` (not `[:text]`).
#
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'BSV MCP server — protocol integration' do
  # A single server instance shared across the suite — the server is
  # stateless between calls so this is safe.
  let(:server) { BSV::MCP::Server.build }

  # Build a well-formed JSON-RPC 2.0 request hash.
  # +req_id+ defaults to 1 and can be varied to avoid id collisions in examples.
  # Ruby 2.7 interprets a trailing symbol-keyed hash as keyword args, so
  # +req_id+ is positional (with a default) to avoid the ambiguity.
  def rpc(method, params = nil, req_id = 1)
    req = { jsonrpc: '2.0', id: req_id, method: method }
    req[:params] = params if params
    req
  end

  # Parse the first content item's text payload from a tools/call response.
  def payload_from(response)
    JSON.parse(response[:result][:content].first.text, symbolize_names: true)
  end

  # ------------------------------------------------------------------
  # initialize
  # ------------------------------------------------------------------
  describe 'initialize' do
    let(:init_params) do
      {
        protocolVersion: '2025-03-26',
        clientInfo: { name: 'test-client', version: '0.1' },
        capabilities: {}
      }
    end

    it 'responds with serverInfo containing the correct name' do
      response = server.handle(rpc('initialize', init_params))
      expect(response[:result][:serverInfo][:name]).to eq('bsv-sdk')
    end

    it 'responds with the correct version' do
      response = server.handle(rpc('initialize', init_params))
      expect(response[:result][:serverInfo][:version]).to eq(BSV::VERSION)
    end

    it 'echoes back a supported protocol version' do
      response = server.handle(rpc('initialize', init_params))
      expect(response[:result][:protocolVersion]).to be_a(String)
      expect(response[:result][:protocolVersion]).not_to be_empty
    end

    it 'advertises tools capability' do
      response = server.handle(rpc('initialize', init_params))
      expect(response[:result][:capabilities]).to have_key(:tools)
    end
  end

  # ------------------------------------------------------------------
  # tools/list
  # ------------------------------------------------------------------
  describe 'tools/list' do
    it 'returns all six tools' do
      response = server.handle(rpc('tools/list'))
      tool_names = response[:result][:tools].map { |t| t[:name] }

      expect(tool_names).to contain_exactly(
        'generate_key',
        'decode_tx',
        'fetch_utxos',
        'fetch_tx',
        'check_balance',
        'broadcast_p2pkh'
      )
    end

    it 'returns tool names in snake_case (MCP convention)' do
      response = server.handle(rpc('tools/list'))
      names = response[:result][:tools].map { |t| t[:name] }

      expect(names).to all(match(/\A[a-z][a-z0-9_]*\z/))
    end

    it 'includes an inputSchema for every tool' do
      response = server.handle(rpc('tools/list'))
      schemas = response[:result][:tools].map { |t| t[:inputSchema] }

      expect(schemas).to all(be_a(Hash))
    end

    it 'includes a non-empty description for every tool' do
      response = server.handle(rpc('tools/list'))
      descriptions = response[:result][:tools].map { |t| t[:description] }

      expect(descriptions).to all(be_a(String))
      expect(descriptions).to all(satisfy { |d| !d.empty? })
    end

    it 'returns a success response (no JSON-RPC error)' do
      response = server.handle(rpc('tools/list'))

      expect(response).not_to have_key(:error)
      expect(response[:result]).to have_key(:tools)
    end
  end

  # ------------------------------------------------------------------
  # tools/call — generate_key
  # ------------------------------------------------------------------
  describe 'tools/call — generate_key' do
    let(:call_request) do
      rpc('tools/call', { name: 'generate_key', arguments: {} })
    end

    it 'returns a success response (no JSON-RPC error)' do
      response = server.handle(call_request)
      expect(response).not_to have_key(:error)
    end

    it 'returns a non-empty content array' do
      response = server.handle(call_request)
      expect(response[:result][:content]).to be_an(Array)
      expect(response[:result][:content]).not_to be_empty
    end

    it 'returns an MCP::Content::Text object as the first content item' do
      response = server.handle(call_request)
      expect(response[:result][:content].first).to be_a(MCP::Content::Text)
    end

    it 'returns parseable JSON in the text field' do
      response = server.handle(call_request)
      text = response[:result][:content].first.text
      expect { JSON.parse(text) }.not_to raise_error
    end

    it 'returns a WIF key in the payload' do
      payload = payload_from(server.handle(call_request))
      expect(payload[:wif]).to be_a(String)
      expect(payload[:wif]).not_to be_empty
    end

    it 'returns a 66-character compressed public key hex' do
      payload = payload_from(server.handle(call_request))
      expect(payload[:public_key_hex]).to match(/\A[0-9a-f]{66}\z/)
    end

    it 'returns a mainnet address starting with 1' do
      payload = payload_from(server.handle(call_request))
      expect(payload[:address]).to start_with('1')
    end

    it 'produces a different key on each call' do
      payload_a = payload_from(server.handle(call_request))
      payload_b = payload_from(server.handle(call_request))
      expect(payload_a[:wif]).not_to eq(payload_b[:wif])
    end

    it 'returns a WIF that round-trips to the advertised public key' do
      payload = payload_from(server.handle(call_request))
      key = BSV::Primitives::PrivateKey.from_wif(payload[:wif])
      expect(key.public_key.to_hex).to eq(payload[:public_key_hex])
    end
  end

  # ------------------------------------------------------------------
  # tools/call — decode_tx
  # ------------------------------------------------------------------
  describe 'tools/call — decode_tx' do
    # Minimal 1-input / 1-output transaction (version 1):
    #   input:  prev=all-zeros, vout=0xffffffff, script=0xdeadbeef, seq=0xffffffff
    #   output: 1 satoshi, empty locking script
    #   locktime: 0
    let(:known_tx_hex) do
      '0100000001' \
        '0000000000000000000000000000000000000000000000000000000000000000' \
        'ffffffff' \
        '04deadbeef' \
        'ffffffff' \
        '01' \
        '0100000000000000' \
        '00' \
        '00000000'
    end

    # Verified by parsing with BSV::Transaction::Transaction.from_hex.
    let(:expected_txid) { '45200ad773a26a07189cb2390853f608ff7237e092fe182aa896ea0a013dc2eb' }

    let(:call_request) do
      rpc('tools/call', { name: 'decode_tx', arguments: { hex: known_tx_hex } })
    end

    it 'returns a success response (no JSON-RPC error)' do
      response = server.handle(call_request)
      expect(response).not_to have_key(:error)
    end

    it 'decodes the correct txid' do
      payload = payload_from(server.handle(call_request))
      expect(payload[:txid]).to eq(expected_txid)
    end

    it 'decodes version 1' do
      payload = payload_from(server.handle(call_request))
      expect(payload[:version]).to eq(1)
    end

    it 'decodes lock_time 0' do
      payload = payload_from(server.handle(call_request))
      expect(payload[:lock_time]).to eq(0)
    end

    it 'decodes one input' do
      payload = payload_from(server.handle(call_request))
      expect(payload[:inputs].length).to eq(1)
    end

    it 'decodes one output' do
      payload = payload_from(server.handle(call_request))
      expect(payload[:outputs].length).to eq(1)
    end

    it 'returns a tool-level error payload for invalid hex' do
      # Tool-level errors: the RPC call succeeds (no [:error] key) but the
      # tool sets isError in the result and returns an {error:} JSON payload.
      bad_request = rpc('tools/call', { name: 'decode_tx', arguments: { hex: 'notvalidhex' } }, 2)
      payload = payload_from(server.handle(bad_request))

      expect(payload[:error]).to be_a(String)
      expect(payload[:error]).not_to be_empty
    end
  end

  # ------------------------------------------------------------------
  # Error handling — unknown tool name
  # ------------------------------------------------------------------
  describe 'tools/call with an unknown tool name' do
    it 'returns a JSON-RPC error response' do
      response = server.handle(rpc('tools/call', { name: 'no_such_tool', arguments: {} }, 3))

      expect(response[:error]).to be_a(Hash)
      expect(response[:error][:code]).to be_an(Integer)
    end
  end

  # ------------------------------------------------------------------
  # Error handling — missing required argument
  # ------------------------------------------------------------------
  describe 'tools/call with missing required argument' do
    it 'returns an error when the required hex argument is absent' do
      response = server.handle(rpc('tools/call', { name: 'decode_tx', arguments: {} }, 4))

      # mcp >= 0.15 returns a tool-level error (isError in :result) rather
      # than a JSON-RPC error (top-level :error key).
      has_jsonrpc_error = response.key?(:error)
      has_tool_error = response.dig(:result, :isError) == true
      expect(has_jsonrpc_error || has_tool_error).to be true
    end
  end
end
# rubocop:enable RSpec/DescribeClass
