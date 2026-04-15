# frozen_string_literal: true

RSpec.describe BSV::WireFormat do
  describe '.snake_to_camel' do
    it 'converts a simple snake_case string' do
      expect(described_class.snake_to_camel('identity_key')).to eq('identityKey')
    end

    it 'uses the lookup table for known acronym keys' do
      expect(described_class.snake_to_camel('protocol_id')).to eq('protocolID')
    end

    it 'uses the lookup table for input_beef' do
      expect(described_class.snake_to_camel('input_beef')).to eq('inputBEEF')
    end

    it 'uses generic conversion for unknown keys' do
      expect(described_class.snake_to_camel('my_custom_key')).to eq('myCustomKey')
    end

    it 'returns single-word strings unchanged' do
      expect(described_class.snake_to_camel('txid')).to eq('txid')
    end
  end

  describe '.camel_to_snake' do
    it 'converts a simple camelCase string' do
      expect(described_class.camel_to_snake('identityKey')).to eq('identity_key')
    end

    it 'uses the lookup table for known acronym keys' do
      expect(described_class.camel_to_snake('protocolID')).to eq('protocol_id')
    end

    it 'uses the lookup table for inputBEEF' do
      expect(described_class.camel_to_snake('inputBEEF')).to eq('input_beef')
    end

    it 'uses generic conversion for unknown keys' do
      expect(described_class.camel_to_snake('myCustomKey')).to eq('my_custom_key')
    end

    it 'returns single-word strings unchanged' do
      expect(described_class.camel_to_snake('txid')).to eq('txid')
    end
  end

  describe '.to_wire' do
    it 'converts snake_case symbol keys to camelCase string keys' do
      result = described_class.to_wire({ identity_key: '02abc' })
      expect(result).to eq({ 'identityKey' => '02abc' })
    end

    it 'converts snake_case string keys to camelCase string keys' do
      result = described_class.to_wire({ 'identity_key' => '02abc' })
      expect(result).to eq({ 'identityKey' => '02abc' })
    end

    it 'handles acronym keys correctly' do
      result = described_class.to_wire({ protocol_id: [2, 'test'] })
      expect(result).to eq({ 'protocolID' => [2, 'test'] })
    end

    it 'returns an empty hash for empty input' do
      expect(described_class.to_wire({})).to eq({})
    end

    it 'raises ArgumentError for nil input' do
      expect { described_class.to_wire(nil) }.to raise_error(ArgumentError)
    end

    it 'deeply converts nested hash values' do
      result = described_class.to_wire({ outer_key: { inner_key: 'value' } })
      expect(result).to eq({ 'outerKey' => { 'innerKey' => 'value' } })
    end

    it 'deeply converts hashes inside arrays' do
      result = described_class.to_wire({ actions: [{ label_query_mode: 'any' }] })
      expect(result).to eq({ 'actions' => [{ 'labelQueryMode' => 'any' }] })
    end

    it 'passes non-hash array elements through unchanged' do
      result = described_class.to_wire({ data: [1, 'hello', { my_key: 1 }] })
      expect(result).to eq({ 'data' => [1, 'hello', { 'myKey' => 1 }] })
    end

    it 'does not convert values (only keys)' do
      result = described_class.to_wire({ my_key: 'some_snake_value' })
      expect(result).to eq({ 'myKey' => 'some_snake_value' })
    end

    it 'converts all BRC-103 handshake keys' do
      input = {
        message_type: 'initialRequest',
        identity_key: '02abc',
        initial_nonce: 'nonce123',
        your_nonce: 'nonce456',
        requested_certificates: [],
        serial_number: 'sn001',
        revocation_outpoint: 'txid:0'
      }
      expected = {
        'messageType' => 'initialRequest',
        'identityKey' => '02abc',
        'initialNonce' => 'nonce123',
        'yourNonce' => 'nonce456',
        'requestedCertificates' => [],
        'serialNumber' => 'sn001',
        'revocationOutpoint' => 'txid:0'
      }
      expect(described_class.to_wire(input)).to eq(expected)
    end
  end

  describe '.from_wire' do
    it 'converts camelCase string keys to snake_case symbol keys' do
      result = described_class.from_wire({ 'identityKey' => '02abc' })
      expect(result).to eq({ identity_key: '02abc' })
    end

    it 'handles acronym keys correctly' do
      result = described_class.from_wire({ 'protocolID' => [2, 'test'] })
      expect(result).to eq({ protocol_id: [2, 'test'] })
    end

    it 'returns an empty hash for empty input' do
      expect(described_class.from_wire({})).to eq({})
    end

    it 'raises ArgumentError for nil input' do
      expect { described_class.from_wire(nil) }.to raise_error(ArgumentError)
    end

    it 'deeply converts nested hash values' do
      result = described_class.from_wire({ 'outerKey' => { 'innerKey' => 'value' } })
      expect(result).to eq({ outer_key: { inner_key: 'value' } })
    end

    it 'deeply converts hashes inside arrays' do
      result = described_class.from_wire({ 'actions' => [{ 'labelQueryMode' => 'any' }] })
      expect(result).to eq({ actions: [{ label_query_mode: 'any' }] })
    end

    it 'passes non-hash array elements through unchanged' do
      result = described_class.from_wire({ 'data' => [1, 'hello', { 'myKey' => 1 }] })
      expect(result).to eq({ data: [1, 'hello', { my_key: 1 }] })
    end

    it 'does not convert values (only keys)' do
      result = described_class.from_wire({ 'myKey' => 'someCamelValue' })
      expect(result).to eq({ my_key: 'someCamelValue' })
    end

    it 'converts all BRC-103 handshake keys' do
      input = {
        'messageType' => 'initialRequest',
        'identityKey' => '02abc',
        'initialNonce' => 'nonce123',
        'yourNonce' => 'nonce456',
        'requestedCertificates' => [],
        'serialNumber' => 'sn001',
        'revocationOutpoint' => 'txid:0'
      }
      expected = {
        message_type: 'initialRequest',
        identity_key: '02abc',
        initial_nonce: 'nonce123',
        your_nonce: 'nonce456',
        requested_certificates: [],
        serial_number: 'sn001',
        revocation_outpoint: 'txid:0'
      }
      expect(described_class.from_wire(input)).to eq(expected)
    end
  end

  describe '.shallow_to_wire' do
    it 'converts top-level keys only' do
      result = described_class.shallow_to_wire({ identity_key: '02abc', your_nonce: 'n1' })
      expect(result).to eq({ 'identityKey' => '02abc', 'yourNonce' => 'n1' })
    end

    it 'does NOT recurse into nested hashes' do
      input = {
        requested_certificates: {
          'certifiers' => ['02abc'],
          'types' => { 'dHlwZUFBQQ==' => %w[name email] }
        }
      }
      result = described_class.shallow_to_wire(input)
      # The nested hash should be passed through unchanged — keys not converted
      expect(result['requestedCertificates']['types']).to eq({ 'dHlwZUFBQQ==' => %w[name email] })
    end

    it 'preserves base64 certificate type keys in requested_certificates' do
      cert_types = { 'dHlwZUFBQUFBQQ==' => %w[name email], 'Zm9vQmFy' => ['age'] }
      input = { requested_certificates: { 'certifiers' => [], 'types' => cert_types } }
      result = described_class.shallow_to_wire(input)
      expect(result['requestedCertificates']['types'].keys).to eq(%w[dHlwZUFBQUFBQQ== Zm9vQmFy])
    end

    it 'raises ArgumentError for nil input' do
      expect { described_class.shallow_to_wire(nil) }.to raise_error(ArgumentError)
    end
  end

  describe '.shallow_from_wire' do
    it 'converts top-level keys only' do
      result = described_class.shallow_from_wire({ 'identityKey' => '02abc', 'yourNonce' => 'n1' })
      expect(result).to eq({ identity_key: '02abc', your_nonce: 'n1' })
    end

    it 'does NOT recurse into nested hashes' do
      input = {
        'requestedCertificates' => {
          'certifiers' => ['02abc'],
          'types' => { 'dHlwZUFBQQ==' => %w[name email] }
        }
      }
      result = described_class.shallow_from_wire(input)
      # The nested hash should be passed through unchanged — keys not converted
      expect(result[:requested_certificates]['types']).to eq({ 'dHlwZUFBQQ==' => %w[name email] })
    end

    it 'preserves base64 certificate type keys in requested_certificates' do
      cert_types = { 'dHlwZUFBQUFBQQ==' => %w[name email], 'Zm9vQmFy' => ['age'] }
      input = { 'requestedCertificates' => { 'certifiers' => [], 'types' => cert_types } }
      result = described_class.shallow_from_wire(input)
      expect(result[:requested_certificates]['types'].keys).to eq(%w[dHlwZUFBQUFBQQ== Zm9vQmFy])
    end

    it 'raises ArgumentError for nil input' do
      expect { described_class.shallow_from_wire(nil) }.to raise_error(ArgumentError)
    end
  end

  describe 'round-trip' do
    it 'round-trips a representative BRC-100 payload' do
      original = {
        identity_key: '02abcdef',
        protocol_id: [2, 'test-protocol'],
        key_id: 'my-key',
        locking_script: 'deadbeef',
        include_labels: true,
        label_query_mode: 'any'
      }
      expect(described_class.from_wire(described_class.to_wire(original))).to eq(original)
    end

    it 'round-trips deeply nested structures' do
      original = {
        outputs: [
          { locking_script: 'abc', include_tags: false },
          { locking_script: 'def', include_tags: true }
        ],
        identity_key: '02abc'
      }
      expect(described_class.from_wire(described_class.to_wire(original))).to eq(original)
    end
  end
end
