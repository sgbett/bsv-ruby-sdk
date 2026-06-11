# frozen_string_literal: true

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'BSV::Wallet loopback integration (WalletWireTransceiver → WalletWireProcessor → ProtoWallet)' do
  let(:private_key) { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(42)) }
  let(:other_key)   { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(99)) }

  let(:proto)     { BSV::Wallet::ProtoWallet.new(private_key) }
  let(:processor) { BSV::Wallet::WalletWireProcessor.new(proto) }
  let(:client)    { BSV::Wallet::WalletWireTransceiver.new(processor) }

  let(:protocol_id) { [1, 'test proto'] }
  let(:key_id)      { 'key-1' }

  # -------------------------------------------------------------------------
  # WalletWire module
  # -------------------------------------------------------------------------

  describe 'WalletWire' do
    it 'is included by WalletWireProcessor' do
      expect(processor).to be_a(BSV::Wallet::WalletWire)
    end

    it 'raises NotImplementedError when transmit_to_wallet is not overridden' do
      bare = Object.new
      bare.extend(BSV::Wallet::WalletWire)
      expect { bare.transmit_to_wallet(''.b) }.to raise_error(NotImplementedError)
    end
  end

  # -------------------------------------------------------------------------
  # WalletWireTransceiver includes Interface::BRC100
  # -------------------------------------------------------------------------

  describe 'WalletWireTransceiver' do
    it 'includes Interface::BRC100' do
      expect(client).to be_a(BSV::Wallet::Interface::BRC100)
    end

    it 'rejects oversize originators before serialisation' do
      expect { client.get_public_key(identity_key: true, originator: 'x' * 251) }
        .to raise_error(BSV::Wallet::InvalidParameterError, /at most 250 bytes/)
    end
  end

  # -------------------------------------------------------------------------
  # get_public_key
  # -------------------------------------------------------------------------

  describe '#get_public_key' do
    # Per ADR-001 the Ruby return shape is hex (BRC-100 PubKeyHex);
    # wire bytes remain 33-byte compressed binary.
    it 'returns the identity public key as hex matching ProtoWallet' do
      direct = proto.get_public_key(identity_key: true)[:public_key]
      wire   = client.get_public_key(identity_key: true)
      expect(wire[:public_key]).to eq(direct)
    end

    it 'returns a derived public key as hex matching ProtoWallet' do
      direct = proto.get_public_key(protocol_id: protocol_id, key_id: key_id, counterparty: 'self')[:public_key]
      wire   = client.get_public_key(protocol_id: protocol_id, key_id: key_id, counterparty: 'self')
      expect(wire[:public_key]).to eq(direct)
    end

    it 'returns a 66-char compressed-pubkey hex string' do
      wire = client.get_public_key(identity_key: true)
      expect(wire[:public_key]).to be_a(String)
      expect(wire[:public_key]).to match(/\A0[23][0-9a-fA-F]{64}\z/)
    end
  end

  # -------------------------------------------------------------------------
  # authenticated? (call byte 23 — predicate suffix)
  # -------------------------------------------------------------------------

  describe '#authenticated?' do
    it 'raises UnsupportedActionError because ProtoWallet does not implement it' do
      expect { client.authenticated? }.to raise_error(BSV::Wallet::UnsupportedActionError)
    end

    it 'dispatches to :authenticated? not :is_authenticated on the wallet' do
      spy = Class.new do
        include BSV::Wallet::Interface::BRC100

        attr_reader :calls

        # rubocop:disable Naming/PredicateMethod
        def authenticated?(**_args)
          @calls ||= []
          @calls << :authenticated?
          { authenticated: true }
        end
        # rubocop:enable Naming/PredicateMethod
      end.new

      spy_client = BSV::Wallet::WalletWireTransceiver.new(
        BSV::Wallet::WalletWireProcessor.new(spy)
      )
      result = spy_client.authenticated?
      expect(spy.calls).to include(:authenticated?)
      expect(result[:authenticated]).to be(true)
    end
  end

  # -------------------------------------------------------------------------
  # encrypt / decrypt round-trip
  # -------------------------------------------------------------------------

  describe '#encrypt and #decrypt' do
    let(:plaintext) { ("\xAB" * 100).b }

    it 'round-trips a 100-byte plaintext through the wire' do
      enc = client.encrypt(
        plaintext: plaintext,
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: 'self'
      )
      expect(enc[:ciphertext]).to be_a(String)
      expect(enc[:ciphertext].encoding).to eq(Encoding::ASCII_8BIT)
      expect(enc[:ciphertext]).not_to eq(plaintext)

      dec = client.decrypt(
        ciphertext: enc[:ciphertext],
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: 'self'
      )
      expect(dec[:plaintext]).to eq(plaintext)
    end

    it 'returns binary-string ciphertext (not Array)' do
      enc = client.encrypt(
        plaintext: 'hello'.b,
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: 'self'
      )
      expect(enc[:ciphertext]).to be_a(String)
    end
  end

  # -------------------------------------------------------------------------
  # create_hmac / verify_hmac
  # -------------------------------------------------------------------------

  describe '#create_hmac and #verify_hmac' do
    let(:data) { 'test data for HMAC'.b }

    it 'creates and verifies an HMAC through the wire' do
      hmac_result = client.create_hmac(
        data: data,
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: 'self'
      )
      expect(hmac_result[:hmac]).to be_a(String)
      expect(hmac_result[:hmac].bytesize).to eq(32)

      verify_result = client.verify_hmac(
        data: data,
        hmac: hmac_result[:hmac],
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: 'self'
      )
      expect(verify_result[:valid]).to be(true)
    end

    it 'raises WERR_INVALID_HMAC when the HMAC is tampered' do
      hmac_result = client.create_hmac(
        data: data,
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: 'self'
      )
      bad_hmac = hmac_result[:hmac].bytes.map { |b| b ^ 0xFF }.pack('C*')
      expect do
        client.verify_hmac(
          data: data,
          hmac: bad_hmac,
          protocol_id: protocol_id,
          key_id: key_id,
          counterparty: 'self'
        )
      end.to raise_error(BSV::Wallet::InvalidHmacError)
    end
  end

  # -------------------------------------------------------------------------
  # create_signature / verify_signature
  # -------------------------------------------------------------------------

  describe '#create_signature and #verify_signature' do
    let(:data) { 'hello bsv!'.b }

    it 'creates and verifies a signature through the wire' do
      sig_result = client.create_signature(
        data: data,
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: 'anyone'
      )
      expect(sig_result[:signature]).to be_a(String)
      expect(sig_result[:signature].bytesize).to be > 0

      verify_result = client.verify_signature(
        data: data,
        signature: sig_result[:signature],
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: 'anyone',
        for_self: true
      )
      expect(verify_result[:valid]).to be(true)
    end

    it 'raises WERR_INVALID_SIGNATURE for a bad signature through the wire' do
      bad_sig = client.create_signature(
        data: 'other data'.b,
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: 'anyone'
      )
      expect do
        client.verify_signature(
          data: data,
          signature: bad_sig[:signature],
          protocol_id: protocol_id,
          key_id: key_id,
          counterparty: 'anyone',
          for_self: true
        )
      end.to raise_error(BSV::Wallet::InvalidSignatureError)
    end
  end

  # -------------------------------------------------------------------------
  # reveal_counterparty_key_linkage
  # -------------------------------------------------------------------------

  describe '#reveal_counterparty_key_linkage' do
    let(:other_pubkey) { other_key.public_key.to_hex }

    it 'returns linkage data through the wire' do
      result = client.reveal_counterparty_key_linkage(
        counterparty: other_pubkey,
        verifier: other_pubkey
      )
      expect(result[:encrypted_linkage]).to be_a(String)
      expect(result[:encrypted_linkage_proof]).to be_a(String)
      expect(result[:revelation_time]).to be_a(String)
    end
  end

  # -------------------------------------------------------------------------
  # reveal_specific_key_linkage
  # -------------------------------------------------------------------------

  describe '#reveal_specific_key_linkage' do
    let(:other_pubkey) { other_key.public_key.to_hex }

    it 'returns specific linkage data through the wire' do
      result = client.reveal_specific_key_linkage(
        counterparty: other_pubkey,
        verifier: other_pubkey,
        protocol_id: protocol_id,
        key_id: key_id
      )
      expect(result[:encrypted_linkage]).to be_a(String)
      expect(result[:proof_type]).to be_a(Integer)
    end
  end

  # -------------------------------------------------------------------------
  # Unsupported methods → WERR_UNSUPPORTED_ACTION
  # -------------------------------------------------------------------------

  describe 'unsupported methods' do
    it 'raises UnsupportedActionError for create_action' do
      expect do
        client.create_action(description: 'test action', outputs: [])
      end.to raise_error(BSV::Wallet::UnsupportedActionError)
    end

    it 'raises UnsupportedActionError for list_outputs' do
      expect do
        client.list_outputs(basket: 'default')
      end.to raise_error(BSV::Wallet::UnsupportedActionError)
    end

    it 'raises UnsupportedActionError for get_height' do
      expect { client.get_height }.to raise_error(BSV::Wallet::UnsupportedActionError)
    end

    it 'raises UnsupportedActionError for get_network' do
      expect { client.get_network }.to raise_error(BSV::Wallet::UnsupportedActionError)
    end
  end

  # -------------------------------------------------------------------------
  # Originator round-trip
  # -------------------------------------------------------------------------

  describe 'originator passing' do
    let(:spy_wallet) do
      Class.new do
        include BSV::Wallet::Interface::BRC100

        attr_reader :last_originator

        def get_public_key(**args)
          @last_originator = args[:originator]
          { public_key: '0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798' }
        end
      end.new
    end

    let(:spy_processor) { BSV::Wallet::WalletWireProcessor.new(spy_wallet) }
    let(:spy_client)    { BSV::Wallet::WalletWireTransceiver.new(spy_processor) }

    it 'passes originator to the wallet method' do
      spy_client.get_public_key(identity_key: true, originator: 'app.example')
      expect(spy_wallet.last_originator).to eq('app.example')
    end

    it 'does not inject originator key when originator is empty' do
      spy_client.get_public_key(identity_key: true)
      expect(spy_wallet.last_originator).to be_nil
    end

    it 'does not inject originator key when originator is empty string' do
      spy_client.get_public_key(identity_key: true, originator: '')
      expect(spy_wallet.last_originator).to be_nil
    end
  end

  # -------------------------------------------------------------------------
  # Error frame rehydration
  # -------------------------------------------------------------------------

  describe 'wire frame error path' do
    it 'rehydrates WERR_INVALID_PARAMETER (code 6) from an error frame' do
      error_wallet = Class.new do
        include BSV::Wallet::Interface::BRC100

        def get_public_key(**_args)
          raise BSV::Wallet::InvalidParameterError.new('protocol_id', 'a valid protocol')
        end
      end.new

      error_client = BSV::Wallet::WalletWireTransceiver.new(
        BSV::Wallet::WalletWireProcessor.new(error_wallet)
      )
      expect { error_client.get_public_key(identity_key: true) }
        .to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rehydrates WERR_INVALID_HMAC (code 3) as InvalidHmacError' do
      hmac_wallet = Class.new do
        include BSV::Wallet::Interface::BRC100

        def verify_hmac(**_args)
          raise BSV::Wallet::InvalidHmacError
        end
      end.new

      hmac_client = BSV::Wallet::WalletWireTransceiver.new(
        BSV::Wallet::WalletWireProcessor.new(hmac_wallet)
      )
      expect do
        hmac_client.verify_hmac(
          data: 'x'.b,
          hmac: ("\x00" * 32).b,
          protocol_id: [1, 'test proto'],
          key_id: 'k',
          counterparty: 'self'
        )
      end.to raise_error(BSV::Wallet::InvalidHmacError)
    end
  end

  # -------------------------------------------------------------------------
  # Malformed frame handling (processor boundary)
  # -------------------------------------------------------------------------

  describe 'malformed frame handling' do
    it 'returns an error frame for empty bytes' do
      result = processor.transmit_to_wallet(''.b)
      expect(result.getbyte(0)).not_to eq(0)
    end

    it 'returns an error frame for an unknown call byte' do
      unknown_frame = BSV::Wallet::Wire::Frame.write_request(call: 255, originator: '', params: ''.b)
      result = processor.transmit_to_wallet(unknown_frame)
      expect(result.getbyte(0)).not_to eq(0)
    end

    it 'returns an error frame for truncated params on a real call' do
      frame = BSV::Wallet::Wire::Frame.write_request(
        call: BSV::Wallet::Wire::Calls::ENCRYPT,
        originator: '',
        params: "\x00".b
      )
      result = processor.transmit_to_wallet(frame)
      expect(result.getbyte(0)).not_to eq(0)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
