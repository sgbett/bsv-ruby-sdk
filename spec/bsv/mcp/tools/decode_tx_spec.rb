# frozen_string_literal: true

RSpec.describe 'BSV::MCP::Tools::DecodeTx' do
  subject(:tool) { BSV::MCP::Tools::DecodeTx }

  # Minimal valid coinbase-style transaction (1 input, 1 output):
  #   version: 1
  #   input: prev_txid all-zeros, vout 0xffffffff, script 0xdeadbeef, sequence 0xffffffff
  #   output: 1 satoshi, empty locking script
  #   locktime: 0
  let(:simple_tx_hex) do
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

  # A minimal P2PKH output transaction for type detection
  let(:p2pkh_output_tx_hex) do
    # version=1, 1 input (coinbase), 1 output (P2PKH to a 20-byte zero hash)
    '01000000' \
      '01' \
      '0000000000000000000000000000000000000000000000000000000000000000' \
      'ffffffff' \
      '00' \
      'ffffffff' \
      '01' \
      'e803000000000000' \
      '19' \
      '76a914000000000000000000000000000000000000000088ac' \
      '00000000'
  end

  describe '.call' do
    context 'with a valid transaction hex' do
      it 'returns an MCP::Tool::Response' do
        response = tool.call(hex: simple_tx_hex)
        expect(response).to be_a(MCP::Tool::Response)
      end

      it 'is not an error response' do
        response = tool.call(hex: simple_tx_hex)
        expect(response.error?).to be false
      end

      it 'returns a txid' do
        result = JSON.parse(tool.call(hex: simple_tx_hex).content.first.text, symbolize_names: true)
        expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
      end

      it 'returns version 1' do
        result = JSON.parse(tool.call(hex: simple_tx_hex).content.first.text, symbolize_names: true)
        expect(result[:version]).to eq(1)
      end

      it 'returns lock_time 0' do
        result = JSON.parse(tool.call(hex: simple_tx_hex).content.first.text, symbolize_names: true)
        expect(result[:lock_time]).to eq(0)
      end

      it 'returns one input' do
        result = JSON.parse(tool.call(hex: simple_tx_hex).content.first.text, symbolize_names: true)
        expect(result[:inputs].length).to eq(1)
      end

      it 'returns one output' do
        result = JSON.parse(tool.call(hex: simple_tx_hex).content.first.text, symbolize_names: true)
        expect(result[:outputs].length).to eq(1)
      end

      it 'shows the input prev_txid in display byte order (hex string)' do
        result = JSON.parse(tool.call(hex: simple_tx_hex).content.first.text, symbolize_names: true)
        expect(result[:inputs].first[:prev_txid]).to match(/\A[0-9a-f]{64}\z/)
      end

      it 'shows the input vout' do
        result = JSON.parse(tool.call(hex: simple_tx_hex).content.first.text, symbolize_names: true)
        expect(result[:inputs].first[:vout]).to be_an(Integer)
      end

      it 'shows output satoshis' do
        result = JSON.parse(tool.call(hex: simple_tx_hex).content.first.text, symbolize_names: true)
        expect(result[:outputs].first[:satoshis]).to eq(1)
      end
    end

    context 'with a P2PKH output' do
      it 'detects pubkeyhash script type' do
        result = JSON.parse(tool.call(hex: p2pkh_output_tx_hex).content.first.text, symbolize_names: true)
        expect(result[:outputs].first[:script_type]).to eq('pubkeyhash')
      end

      it 'returns the script in ASM' do
        result = JSON.parse(tool.call(hex: p2pkh_output_tx_hex).content.first.text, symbolize_names: true)
        expect(result[:outputs].first[:script_asm]).to include('OP_DUP')
      end

      it 'returns the script in hex' do
        result = JSON.parse(tool.call(hex: p2pkh_output_tx_hex).content.first.text, symbolize_names: true)
        expect(result[:outputs].first[:script_hex]).to match(/\A[0-9a-f]+\z/)
      end
    end

    context 'with an invalid hex string' do
      it 'returns an error response' do
        response = tool.call(hex: 'notvalidhex')
        expect(response.error?).to be true
      end

      it 'includes an error message' do
        response = tool.call(hex: 'notvalidhex')
        result = JSON.parse(response.content.first.text, symbolize_names: true)
        expect(result[:error]).to be_a(String)
        expect(result[:error]).not_to be_empty
      end
    end

    it 'includes structured_content' do
      response = tool.call(hex: simple_tx_hex)
      expect(response.structured_content).to be_a(Hash)
      expect(response.structured_content[:txid]).to be_a(String)
    end
  end
end
