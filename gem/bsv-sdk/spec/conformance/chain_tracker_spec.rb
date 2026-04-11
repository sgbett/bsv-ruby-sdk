# frozen_string_literal: true

require 'spec_helper'

# Protocol conformance: Chain tracker interface and WhatsOnChain implementation
#
# Cross-validates the Ruby SDK's chain tracker against known block data
# and reference SDK patterns (Go, TS, Python).
#
# Test vectors use the BSV genesis block (height 0) whose merkle root is
# the coinbase txid — a well-known constant across all BSV implementations.

RSpec.describe BSV::Transaction::ChainTrackers::WhatsOnChain do
  # Genesis block (height 0) merkle root = coinbase txid
  let(:genesis_merkle_root) { '4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b' }

  # Block 1 merkle root
  let(:block1_merkle_root) { '0e3e2357e806b6cdb1f70b54c3a3a17b6714ee1f0e68bebb44a74b1efd512098' }

  let(:http_client) { instance_double(Net::HTTP) }
  let(:tracker) { described_class.new(http_client: http_client) }

  def mock_response(code, body)
    instance_double(Net::HTTPResponse, code: code.to_s, body: body)
  end

  def block_header_json(merkle_root, height: 0)
    {
      'hash' => '000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f',
      'confirmations' => 800_000,
      'size' => 285,
      'height' => height,
      'version' => 1,
      'merkleroot' => merkle_root,
      'tx' => [],
      'time' => 1_231_006_505,
      'nonce' => 2_083_236_893,
      'bits' => '1d00ffff',
      'previousblockhash' => '0000000000000000000000000000000000000000000000000000000000000000'
    }.to_json
  end

  describe 'contract conformance' do
    it 'inherits from ChainTracker' do
      expect(described_class.superclass).to eq(BSV::Transaction::ChainTracker)
    end

    it 'implements valid_root_for_height?' do
      expect(tracker).to respond_to(:valid_root_for_height?).with(2).arguments
    end

    it 'implements current_height' do
      expect(tracker).to respond_to(:current_height).with(0).arguments
    end
  end

  describe 'genesis block verification' do
    it 'confirms genesis block merkle root at height 0' do
      allow(http_client).to receive(:request).and_return(
        mock_response(200, block_header_json(genesis_merkle_root, height: 0))
      )

      expect(tracker.valid_root_for_height?(genesis_merkle_root, 0)).to be true
    end

    it 'rejects wrong merkle root at height 0' do
      allow(http_client).to receive(:request).and_return(
        mock_response(200, block_header_json(genesis_merkle_root, height: 0))
      )

      expect(tracker.valid_root_for_height?(block1_merkle_root, 0)).to be false
    end
  end

  describe 'Go SDK test pattern conformance' do
    # Go SDK: TestWhatsOnChainIsValidRootForHeightSuccess
    it 'returns true when root matches (matching Go SDK pattern)' do
      root = 'abcdef1234567890' * 4
      allow(http_client).to receive(:request).and_return(
        mock_response(200, block_header_json(root, height: 100))
      )

      expect(tracker.valid_root_for_height?(root, 100)).to be true
    end

    # Go SDK: TestWhatsOnChainIsValidRootForHeightInvalidRoot
    it 'returns false when root does not match (matching Go SDK pattern)' do
      root = 'abcdef1234567890' * 4
      different_root = '1234567890abcdef' * 4
      allow(http_client).to receive(:request).and_return(
        mock_response(200, block_header_json(root, height: 100))
      )

      expect(tracker.valid_root_for_height?(different_root, 100)).to be false
    end

    # Go SDK: TestWhatsOnChainGetBlockHeaderNotFound
    it 'returns false for 404 (matching Go SDK nil-return pattern)' do
      allow(http_client).to receive(:request).and_return(mock_response(404, 'Not Found'))

      expect(tracker.valid_root_for_height?(genesis_merkle_root, 999_999_999)).to be false
    end

    # Go SDK: TestWhatsOnChainGetBlockHeaderErrorResponse
    it 'raises on 500 (matching Go SDK error pattern)' do
      allow(http_client).to receive(:request).and_return(
        mock_response(500, 'Internal Server Error')
      )

      expect { tracker.valid_root_for_height?(genesis_merkle_root, 100) }
        .to raise_error(BSV::Network::ChainProviderError)
    end

    # Go SDK: TestWhatsOnChainCurrentHeight
    it 'returns current height (matching Go SDK pattern)' do
      allow(http_client).to receive(:request).and_return(
        mock_response(200, { 'chain' => 'main', 'blocks' => 800_000 }.to_json)
      )

      expect(tracker.current_height).to eq(800_000)
    end

    # Go SDK: Authorization header check
    it 'sends API key in Authorization header (matching Go SDK pattern)' do
      keyed = described_class.new(api_key: 'testapikey', http_client: http_client)
      allow(http_client).to receive(:request).and_return(
        mock_response(200, block_header_json(genesis_merkle_root))
      )

      keyed.valid_root_for_height?(genesis_merkle_root, 0)

      expect(http_client).to have_received(:request) do |_uri, req|
        expect(req['Authorization']).to eq('testapikey')
      end
    end
  end

  describe 'end-to-end SPV verification' do
    # BRC-74 test vector from Go SDK (same as merkle_path_spec)
    let(:brc74_hex) do
      'fe8a6a0c000c04fde80b0011774f01d26412f0d16ea3f0447be0b5ebec67b0782e321a7a01cbdf7f734e30' \
        'fde90b02004e53753e3fe4667073063a17987292cfdea278824e9888e52180581d7188d8' \
        'fdea0b025e441996fc53f0191d649e68a200e752fb5f39e0d5617083408fa179ddc5c998' \
        'fdeb0b0102' \
        'fdf405000671394f72237d08a4277f4435e5b6edf7adc272f25effef27cdfe805ce71a81' \
        'fdf50500262bccabec6c4af3ed00cc7a7414edea9c5efa92fb8623dd6160a001450a5282' \
        '01fdfb020101' \
        'fd7c010093b3efca9b77ddec914f8effac691ecb54e2c81d0ab81cbc4c4b93befe418e85' \
        '01bf01015e005881826eb6973c54003a02118fe270f03d46d02681c8bc71cd44c613e86302f8' \
        '012e00e07a2bb8bb75e5accff266022e1e5e6e7b4d6d943a04faadcf2ab4a22f796ff3' \
        '0116008120cafa17309c0bb0e0ffce835286b3a2dcae48e4497ae2d2b7ced4f051507d' \
        '010a00502e59ac92f46543c23006bff855d96f5e648043f0fb87a7a5949e6a9bebae43' \
        '0104001ccd9f8f64f4d0489b30cc815351cf425e0e78ad79a589350e4341ac165dbe45' \
        '010301010000af8764ce7e1cc132ab5ed2229a005c87201c9a5ee15c0f91dd53eff31ab30cd4'
    end

    let(:expected_root) { '57aab6e6fb1b697174ffb64e062c4728f2ffd33ddcfa02a43b64d8cd29b483b4' }

    it 'MerklePath#verify passes with confirming chain tracker' do
      mp = BSV::Transaction::MerklePath.from_hex(brc74_hex)
      txid_hex = mp.path[0][0].hash.reverse.unpack1('H*')

      allow(http_client).to receive(:request).and_return(
        mock_response(200, block_header_json(expected_root, height: 813_706))
      )

      expect(mp.verify(txid_hex, tracker)).to be true
    end

    it 'MerklePath#verify fails with rejecting chain tracker' do
      mp = BSV::Transaction::MerklePath.from_hex(brc74_hex)
      txid_hex = mp.path[0][0].hash.reverse.unpack1('H*')

      # Return a different merkle root — verification should fail
      allow(http_client).to receive(:request).and_return(
        mock_response(200, block_header_json('0000' * 16, height: 813_706))
      )

      expect(mp.verify(txid_hex, tracker)).to be false
    end

    it 'MerklePath#verify fails when block not found' do
      mp = BSV::Transaction::MerklePath.from_hex(brc74_hex)
      txid_hex = mp.path[0][0].hash.reverse.unpack1('H*')

      allow(http_client).to receive(:request).and_return(mock_response(404, 'Not Found'))

      expect(mp.verify(txid_hex, tracker)).to be false
    end
  end

  describe 'URL construction conformance' do
    # Verifies URL pattern matches Go SDK: /block/{height}/header
    it 'constructs correct block header URL' do
      allow(http_client).to receive(:request).and_return(
        mock_response(200, block_header_json(genesis_merkle_root))
      )

      tracker.valid_root_for_height?(genesis_merkle_root, 12_345)

      expect(http_client).to have_received(:request) do |uri, _req|
        expect(uri.to_s).to eq('https://api.whatsonchain.com/v1/bsv/main/block/12345/header')
      end
    end

    # Verifies URL pattern matches Go SDK: /chain/info
    it 'constructs correct chain info URL' do
      allow(http_client).to receive(:request).and_return(
        mock_response(200, { 'blocks' => 800_000 }.to_json)
      )

      tracker.current_height

      expect(http_client).to have_received(:request) do |uri, _req|
        expect(uri.to_s).to eq('https://api.whatsonchain.com/v1/bsv/main/chain/info')
      end
    end
  end
end
