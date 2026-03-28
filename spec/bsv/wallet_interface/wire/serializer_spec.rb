# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'
require 'base64'

# Helper: round-trip a request through serialize/deserialize and return [method, args, originator].
def request_roundtrip(method, args, originator: 'example.com')
  data = BSV::Wallet::Wire::Serializer.serialize_request(method, args, originator: originator)
  BSV::Wallet::Wire::Serializer.deserialize_request(data)
end

# Shared assertion for method and originator identity.
def assert_frame_header(method_out, originator_out, expected_method, expected_originator)
  expect(method_out).to eq(expected_method)
  expect(originator_out).to eq(expected_originator)
end

# Canonical test data — shared across multiple method tests.
TXID_HEX    = ('ab' * 32).freeze
OUTPOINT    = "#{TXID_HEX}.0"
PROTOCOL_ID = [2, 'hello world'].freeze
KEY_ID      = 'test key 1'
CERT_TYPE   = Base64.strict_encode64(('ff' * 16).b).freeze
SERIAL_NUM  = Base64.strict_encode64(('ee' * 16).b).freeze
SIG_HEX     = ('cd' * 35).freeze

def pubkey_hex
  @pubkey_hex ||= BSV::Primitives::PrivateKey.generate.public_key.to_hex
end

def cert_fixture(extra = {})
  {
    type: CERT_TYPE,
    subject: pubkey_hex,
    serial_number: SERIAL_NUM,
    certifier: pubkey_hex,
    revocation_outpoint: OUTPOINT,
    signature: SIG_HEX,
    fields: { 'name' => 'Alice' }
  }.merge(extra)
end

RSpec.describe BSV::Wallet::Wire::Serializer do
  # -------------------------------------------------------------------------
  # Frame basics
  # -------------------------------------------------------------------------

  describe 'serialize_request / deserialize_request — frame header' do
    it 'preserves the originator string' do
      _m, _a, orig = request_roundtrip(:get_height, {}, originator: 'wallet.example.com')
      expect(orig).to eq('wallet.example.com')
    end

    it 'handles an empty originator' do
      _m, _a, orig = request_roundtrip(:get_height, {}, originator: '')
      expect(orig).to eq('')
    end

    it 'handles a nil originator (treated as empty string)' do
      _m, _a, orig = request_roundtrip(:get_height, {}, originator: nil)
      expect(orig).to eq('')
    end

    it 'raises on an unknown method' do
      expect do
        described_class.serialize_request(:unknown_method, {})
      end.to raise_error(ArgumentError, /unknown method/)
    end
  end

  # -------------------------------------------------------------------------
  # Error frame
  # -------------------------------------------------------------------------

  describe 'serialize_error / deserialize_response' do
    it 'encodes a non-zero error code and message' do
      data = described_class.serialize_error(42, 'something went wrong')
      expect do
        described_class.deserialize_response(:get_height, data)
      end.to raise_error(BSV::Wallet::WalletError, 'something went wrong')
    end

    it 'stores the error code on the raised exception' do
      data = described_class.serialize_error(7, 'bad request')
      begin
        described_class.deserialize_response(:get_height, data)
      rescue BSV::Wallet::WalletError => e
        expect(e.code).to eq(7)
      end
    end

    it 'includes a stack trace in the serialised frame (discarded on raise)' do
      data = described_class.serialize_error(1, 'err', stack_trace: 'trace here')
      expect(data.bytesize).to be > 10
    end
  end

  # -------------------------------------------------------------------------
  # Transaction methods (1-6)
  # -------------------------------------------------------------------------

  describe 'createAction (1)' do
    let(:args) do
      {
        description: 'pay someone',
        inputs: [
          {
            outpoint: OUTPOINT,
            unlocking_script: 'aabb',
            input_description: 'spend utxo',
            sequence_number: 0xFFFFFFFE
          }
        ],
        outputs: [
          {
            locking_script: 'deadbeef',
            satoshis: 1000,
            output_description: 'change',
            basket: 'default',
            custom_instructions: nil,
            tags: ['payment']
          }
        ],
        lock_time: nil,
        version: 1,
        labels: ['my-label']
      }
    end

    it 'round-trips the method and originator' do
      m, _a, orig = request_roundtrip(:create_action, args)
      assert_frame_header(m, orig, :create_action, 'example.com')
    end

    it 'preserves description' do
      _m, a, = request_roundtrip(:create_action, args)
      expect(a[:description]).to eq('pay someone')
    end

    it 'preserves inputs' do
      _m, a, = request_roundtrip(:create_action, args)
      expect(a[:inputs].length).to eq(1)
      expect(a[:inputs][0][:outpoint]).to eq(OUTPOINT)
      expect(a[:inputs][0][:unlocking_script]).to eq('aabb')
      expect(a[:inputs][0][:sequence_number]).to eq(0xFFFFFFFE)
    end

    it 'preserves outputs' do
      _m, a, = request_roundtrip(:create_action, args)
      expect(a[:outputs].length).to eq(1)
      expect(a[:outputs][0][:satoshis]).to eq(1000)
      expect(a[:outputs][0][:basket]).to eq('default')
      expect(a[:outputs][0][:tags]).to eq(['payment'])
    end

    it 'preserves version and nil lock_time' do
      _m, a, = request_roundtrip(:create_action, args)
      expect(a[:version]).to eq(1)
      expect(a[:lock_time]).to be_nil
    end

    it 'preserves labels' do
      _m, a, = request_roundtrip(:create_action, args)
      expect(a[:labels]).to eq(['my-label'])
    end

    it 'round-trips nil inputs and outputs' do
      minimal = { description: 'empty', inputs: nil, outputs: nil }
      _m, a, = request_roundtrip(:create_action, minimal)
      expect(a[:inputs]).to be_nil
      expect(a[:outputs]).to be_nil
    end

    it 'round-trips an input with unlocking_script_length (no script yet)' do
      with_len = args.merge(inputs: [
                              {
                                outpoint: OUTPOINT,
                                unlocking_script: nil,
                                unlocking_script_length: 107,
                                input_description: 'unsigned input',
                                sequence_number: nil
                              }
                            ])
      _m, a, = request_roundtrip(:create_action, with_len)
      expect(a[:inputs][0][:unlocking_script]).to be_nil
      expect(a[:inputs][0][:unlocking_script_length]).to eq(107)
      expect(a[:inputs][0][:sequence_number]).to be_nil
    end

    it 'round-trips options when present' do
      with_opts = args.merge(options: {
                               sign_and_process: true,
                               accept_delayed_broadcast: nil,
                               trust_self: 'known',
                               known_txids: [TXID_HEX],
                               return_txid_only: false,
                               no_send: nil,
                               no_send_change: nil,
                               send_with: nil,
                               randomize_outputs: nil
                             })
      _m, a, = request_roundtrip(:create_action, with_opts)
      expect(a[:options][:sign_and_process]).to be(true)
      expect(a[:options][:trust_self]).to eq('known')
      expect(a[:options][:known_txids]).to eq([TXID_HEX])
    end

    it 'round-trips response: txid present' do
      result = { txid: TXID_HEX, tx: nil, no_send_change: nil,
                 send_with_results: nil, signable_transaction: nil }
      data = described_class.serialize_response(:create_action, result)
      out = described_class.deserialize_response(:create_action, data)
      expect(out[:txid]).to eq(TXID_HEX)
    end
  end

  describe 'signAction (2)' do
    let(:ref_b64) { Base64.strict_encode64('reference-bytes') }
    let(:args) do
      {
        spends: {
          0 => { unlocking_script: 'aabbcc', sequence_number: nil }
        },
        reference: ref_b64,
        options: nil
      }
    end

    it 'round-trips the method' do
      m, _a, = request_roundtrip(:sign_action, args)
      expect(m).to eq(:sign_action)
    end

    it 'preserves spends' do
      _m, a, = request_roundtrip(:sign_action, args)
      expect(a[:spends][0][:unlocking_script]).to eq('aabbcc')
      expect(a[:spends][0][:sequence_number]).to be_nil
    end

    it 'preserves reference as base64' do
      _m, a, = request_roundtrip(:sign_action, args)
      expect(a[:reference]).to eq(ref_b64)
    end

    it 'round-trips options when present' do
      with_opts = args.merge(options: {
                               accept_delayed_broadcast: true,
                               return_txid_only: false,
                               no_send: nil,
                               send_with: nil
                             })
      _m, a, = request_roundtrip(:sign_action, with_opts)
      expect(a[:options][:accept_delayed_broadcast]).to be(true)
    end
  end

  describe 'abortAction (3)' do
    let(:ref_b64) { Base64.strict_encode64('abort-ref') }
    let(:args) { { reference: ref_b64 } }

    it 'round-trips the method' do
      m, _a, = request_roundtrip(:abort_action, args)
      expect(m).to eq(:abort_action)
    end

    it 'preserves reference as base64' do
      _m, a, = request_roundtrip(:abort_action, args)
      expect(a[:reference]).to eq(ref_b64)
    end

    it 'round-trips response returning aborted: true' do
      data = described_class.serialize_response(:abort_action, {})
      out = described_class.deserialize_response(:abort_action, data)
      expect(out[:aborted]).to be(true)
    end
  end

  describe 'listActions (4)' do
    let(:args) do
      {
        labels: %w[tag1 tag2],
        label_query_mode: 'any',
        include_labels: true,
        include_inputs: false,
        include_input_source_locking_scripts: nil,
        include_input_unlocking_scripts: nil,
        include_outputs: true,
        include_output_locking_scripts: nil,
        limit: 10,
        offset: 0,
        seek_permission: nil
      }
    end

    it 'round-trips the method' do
      m, _a, = request_roundtrip(:list_actions, args)
      expect(m).to eq(:list_actions)
    end

    it 'preserves labels' do
      _m, a, = request_roundtrip(:list_actions, args)
      expect(a[:labels]).to eq(%w[tag1 tag2])
    end

    it 'preserves label_query_mode' do
      _m, a, = request_roundtrip(:list_actions, args)
      expect(a[:label_query_mode]).to eq('any')
    end

    it 'preserves include flags' do
      _m, a, = request_roundtrip(:list_actions, args)
      expect(a[:include_labels]).to be(true)
      expect(a[:include_inputs]).to be(false)
      expect(a[:include_input_source_locking_scripts]).to be_nil
    end

    it 'preserves limit and offset' do
      _m, a, = request_roundtrip(:list_actions, args)
      expect(a[:limit]).to eq(10)
      expect(a[:offset]).to eq(0)
    end

    it 'round-trips response with actions' do
      result = {
        total_actions: 1,
        actions: [
          {
            txid: TXID_HEX,
            satoshis: 5000,
            status: 'completed',
            is_outgoing: true,
            description: 'test tx',
            labels: nil,
            version: 1,
            lock_time: 0,
            inputs: nil,
            outputs: nil
          }
        ]
      }
      data = described_class.serialize_response(:list_actions, result)
      out = described_class.deserialize_response(:list_actions, data)
      expect(out[:total_actions]).to eq(1)
      expect(out[:actions][0][:txid]).to eq(TXID_HEX)
      expect(out[:actions][0][:status]).to eq('completed')
    end
  end

  describe 'internalizeAction (5)' do
    let(:sender_key) { pubkey_hex }
    let(:args) do
      {
        tx: [1, 2, 3, 4],
        outputs: [
          {
            output_index: 0,
            protocol: 'wallet payment',
            payment_remittance: {
              sender_identity_key: sender_key,
              derivation_prefix: Base64.strict_encode64('prefix'),
              derivation_suffix: Base64.strict_encode64('suffix')
            }
          },
          {
            output_index: 1,
            protocol: 'basket insertion',
            insertion_remittance: {
              basket: 'my-basket',
              custom_instructions: 'abc',
              tags: ['tag']
            }
          }
        ],
        labels: ['imported'],
        description: 'internalize tx',
        seek_permission: nil
      }
    end

    it 'round-trips the method' do
      m, _a, = request_roundtrip(:internalize_action, args)
      expect(m).to eq(:internalize_action)
    end

    it 'preserves wallet payment output' do
      _m, a, = request_roundtrip(:internalize_action, args)
      out = a[:outputs][0]
      expect(out[:protocol]).to eq('wallet payment')
      expect(out[:payment_remittance][:sender_identity_key]).to eq(sender_key)
    end

    it 'preserves basket insertion output' do
      _m, a, = request_roundtrip(:internalize_action, args)
      out = a[:outputs][1]
      expect(out[:protocol]).to eq('basket insertion')
      expect(out[:insertion_remittance][:basket]).to eq('my-basket')
    end

    it 'preserves description and labels' do
      _m, a, = request_roundtrip(:internalize_action, args)
      expect(a[:description]).to eq('internalize tx')
      expect(a[:labels]).to eq(['imported'])
    end
  end

  describe 'listOutputs (6)' do
    let(:args) do
      {
        basket: 'default',
        tags: ['payment'],
        tag_query_mode: 'all',
        include: 'locking scripts',
        include_custom_instructions: true,
        include_tags: nil,
        include_labels: false,
        limit: 25,
        offset: nil,
        seek_permission: nil
      }
    end

    it 'round-trips the method' do
      m, _a, = request_roundtrip(:list_outputs, args)
      expect(m).to eq(:list_outputs)
    end

    it 'preserves basket and tags' do
      _m, a, = request_roundtrip(:list_outputs, args)
      expect(a[:basket]).to eq('default')
      expect(a[:tags]).to eq(['payment'])
    end

    it 'preserves tag_query_mode and include' do
      _m, a, = request_roundtrip(:list_outputs, args)
      expect(a[:tag_query_mode]).to eq('all')
      expect(a[:include]).to eq('locking scripts')
    end

    it 'preserves nil offset' do
      _m, a, = request_roundtrip(:list_outputs, args)
      expect(a[:offset]).to be_nil
    end
  end

  describe 'relinquishOutput (7)' do
    let(:args) { { basket: 'default', output: OUTPOINT } }

    it 'round-trips the method' do
      m, _a, = request_roundtrip(:relinquish_output, args)
      expect(m).to eq(:relinquish_output)
    end

    it 'preserves basket and output outpoint' do
      _m, a, = request_roundtrip(:relinquish_output, args)
      expect(a[:basket]).to eq('default')
      expect(a[:output]).to eq(OUTPOINT)
    end
  end

  # -------------------------------------------------------------------------
  # Key methods (8-10)
  # -------------------------------------------------------------------------

  describe 'getPublicKey (8)' do
    context 'with identity_key: true' do
      let(:args) { { identity_key: true, privileged: nil, privileged_reason: nil, seek_permission: nil } }

      it 'round-trips the method' do
        m, _a, = request_roundtrip(:get_public_key, args)
        expect(m).to eq(:get_public_key)
      end

      it 'preserves identity_key flag' do
        _m, a, = request_roundtrip(:get_public_key, args)
        expect(a[:identity_key]).to be(true)
      end
    end

    context 'with protocol/key derivation' do
      let(:args) do
        {
          identity_key: false,
          protocol_id: PROTOCOL_ID,
          key_id: KEY_ID,
          counterparty: 'self',
          privileged: nil,
          privileged_reason: nil,
          for_self: true,
          seek_permission: nil
        }
      end

      it 'preserves protocol_id, key_id, and counterparty' do
        _m, a, = request_roundtrip(:get_public_key, args)
        expect(a[:protocol_id]).to eq(PROTOCOL_ID)
        expect(a[:key_id]).to eq(KEY_ID)
        expect(a[:counterparty]).to eq('self')
        expect(a[:for_self]).to be(true)
      end
    end

    it 'round-trips response with a public key' do
      result = { public_key: pubkey_hex }
      data = described_class.serialize_response(:get_public_key, result)
      out = described_class.deserialize_response(:get_public_key, data)
      expect(out[:public_key]).to eq(pubkey_hex)
    end
  end

  describe 'revealCounterpartyKeyLinkage (9)' do
    let(:prover_key) { pubkey_hex }
    let(:verifier_key) { BSV::Primitives::PrivateKey.generate.public_key.to_hex }
    let(:args) do
      {
        privileged: true,
        privileged_reason: 'user consent',
        counterparty: prover_key,
        verifier: verifier_key
      }
    end

    it 'round-trips the method' do
      m, _a, = request_roundtrip(:reveal_counterparty_key_linkage, args)
      expect(m).to eq(:reveal_counterparty_key_linkage)
    end

    it 'preserves counterparty and verifier pubkeys' do
      _m, a, = request_roundtrip(:reveal_counterparty_key_linkage, args)
      expect(a[:counterparty]).to eq(prover_key)
      expect(a[:verifier]).to eq(verifier_key)
    end

    it 'preserves privileged and privileged_reason' do
      _m, a, = request_roundtrip(:reveal_counterparty_key_linkage, args)
      expect(a[:privileged]).to be(true)
      expect(a[:privileged_reason]).to eq('user consent')
    end
  end

  describe 'revealSpecificKeyLinkage (10)' do
    let(:verifier_key) { BSV::Primitives::PrivateKey.generate.public_key.to_hex }
    let(:args) do
      {
        protocol_id: PROTOCOL_ID,
        key_id: KEY_ID,
        counterparty: 'self',
        privileged: nil,
        privileged_reason: nil,
        verifier: verifier_key
      }
    end

    it 'round-trips the method' do
      m, _a, = request_roundtrip(:reveal_specific_key_linkage, args)
      expect(m).to eq(:reveal_specific_key_linkage)
    end

    it 'preserves verifier alongside key params' do
      _m, a, = request_roundtrip(:reveal_specific_key_linkage, args)
      expect(a[:verifier]).to eq(verifier_key)
      expect(a[:protocol_id]).to eq(PROTOCOL_ID)
    end
  end

  # -------------------------------------------------------------------------
  # Crypto methods (11-16)
  # -------------------------------------------------------------------------

  describe 'encrypt (11)' do
    let(:args) do
      {
        protocol_id: PROTOCOL_ID,
        key_id: KEY_ID,
        counterparty: 'self',
        privileged: nil,
        privileged_reason: nil,
        plaintext: [104, 101, 108, 108, 111],
        seek_permission: nil
      }
    end

    it 'round-trips the method' do
      m, _a, = request_roundtrip(:encrypt, args)
      expect(m).to eq(:encrypt)
    end

    it 'preserves plaintext bytes' do
      _m, a, = request_roundtrip(:encrypt, args)
      expect(a[:plaintext]).to eq([104, 101, 108, 108, 111])
    end

    it 'preserves key params' do
      _m, a, = request_roundtrip(:encrypt, args)
      expect(a[:protocol_id]).to eq(PROTOCOL_ID)
      expect(a[:key_id]).to eq(KEY_ID)
      expect(a[:counterparty]).to eq('self')
    end

    it 'round-trips response with ciphertext bytes' do
      result = { ciphertext: [0xDE, 0xAD, 0xBE, 0xEF] }
      data = described_class.serialize_response(:encrypt, result)
      out = described_class.deserialize_response(:encrypt, data)
      expect(out[:ciphertext]).to eq([0xDE, 0xAD, 0xBE, 0xEF])
    end
  end

  describe 'decrypt (12)' do
    let(:args) do
      {
        protocol_id: PROTOCOL_ID,
        key_id: KEY_ID,
        counterparty: 'self',
        privileged: nil,
        privileged_reason: nil,
        ciphertext: [0xDE, 0xAD, 0xBE, 0xEF],
        seek_permission: nil
      }
    end

    it 'round-trips the method' do
      m, _a, = request_roundtrip(:decrypt, args)
      expect(m).to eq(:decrypt)
    end

    it 'preserves ciphertext bytes' do
      _m, a, = request_roundtrip(:decrypt, args)
      expect(a[:ciphertext]).to eq([0xDE, 0xAD, 0xBE, 0xEF])
    end
  end

  describe 'createHmac (13)' do
    let(:args) do
      {
        protocol_id: PROTOCOL_ID,
        key_id: KEY_ID,
        counterparty: 'self',
        privileged: nil,
        privileged_reason: nil,
        data: [1, 2, 3],
        seek_permission: nil
      }
    end

    it 'round-trips the method' do
      m, _a, = request_roundtrip(:create_hmac, args)
      expect(m).to eq(:create_hmac)
    end

    it 'preserves data bytes' do
      _m, a, = request_roundtrip(:create_hmac, args)
      expect(a[:data]).to eq([1, 2, 3])
    end
  end

  describe 'verifyHmac (14)' do
    let(:hmac_bytes) { [0] * 32 }
    let(:args) do
      {
        protocol_id: PROTOCOL_ID,
        key_id: KEY_ID,
        counterparty: 'self',
        privileged: nil,
        privileged_reason: nil,
        hmac: hmac_bytes,
        data: [10, 20, 30],
        seek_permission: nil
      }
    end

    it 'round-trips the method' do
      m, _a, = request_roundtrip(:verify_hmac, args)
      expect(m).to eq(:verify_hmac)
    end

    it 'preserves hmac (fixed 32 bytes) and data' do
      _m, a, = request_roundtrip(:verify_hmac, args)
      expect(a[:hmac]).to eq(hmac_bytes)
      expect(a[:data]).to eq([10, 20, 30])
    end
  end

  describe 'createSignature (15)' do
    context 'with data payload' do
      let(:args) do
        {
          protocol_id: PROTOCOL_ID,
          key_id: KEY_ID,
          counterparty: 'self',
          privileged: nil,
          privileged_reason: nil,
          data: [97, 98, 99],
          seek_permission: nil
        }
      end

      it 'round-trips the method' do
        m, _a, = request_roundtrip(:create_signature, args)
        expect(m).to eq(:create_signature)
      end

      it 'preserves data bytes' do
        _m, a, = request_roundtrip(:create_signature, args)
        expect(a[:data]).to eq([97, 98, 99])
      end
    end

    context 'with hash_to_directly_sign (32 bytes)' do
      let(:hash32) { [0xAB] * 32 }
      let(:args) do
        {
          protocol_id: PROTOCOL_ID,
          key_id: KEY_ID,
          counterparty: 'self',
          privileged: nil,
          privileged_reason: nil,
          hash_to_directly_sign: hash32,
          seek_permission: nil
        }
      end

      it 'preserves hash_to_directly_sign' do
        _m, a, = request_roundtrip(:create_signature, args)
        expect(a[:hash_to_directly_sign]).to eq(hash32)
      end
    end
  end

  describe 'verifySignature (16)' do
    let(:sig_bytes) { [0x30] + ([0x01] * 70) }
    let(:args) do
      {
        protocol_id: PROTOCOL_ID,
        key_id: KEY_ID,
        counterparty: 'self',
        privileged: nil,
        privileged_reason: nil,
        for_self: nil,
        signature: sig_bytes,
        data: [1, 2, 3],
        seek_permission: nil
      }
    end

    it 'round-trips the method' do
      m, _a, = request_roundtrip(:verify_signature, args)
      expect(m).to eq(:verify_signature)
    end

    it 'preserves signature bytes and data' do
      _m, a, = request_roundtrip(:verify_signature, args)
      expect(a[:signature]).to eq(sig_bytes)
      expect(a[:data]).to eq([1, 2, 3])
    end
  end

  # -------------------------------------------------------------------------
  # Certificate methods (17-20)
  # -------------------------------------------------------------------------

  describe 'acquireCertificate (17) — issuance protocol' do
    let(:args) do
      {
        type: CERT_TYPE,
        certifier: pubkey_hex,
        fields: { 'email' => 'alice@example.com' },
        privileged: nil,
        privileged_reason: nil,
        acquisition_protocol: 'issuance',
        certifier_url: 'https://certifier.example.com'
      }
    end

    it 'round-trips the method' do
      m, _a, = request_roundtrip(:acquire_certificate, args)
      expect(m).to eq(:acquire_certificate)
    end

    it 'preserves type and certifier' do
      _m, a, = request_roundtrip(:acquire_certificate, args)
      expect(a[:type]).to eq(CERT_TYPE)
      expect(a[:certifier]).to eq(pubkey_hex)
    end

    it 'preserves fields map' do
      _m, a, = request_roundtrip(:acquire_certificate, args)
      expect(a[:fields]).to eq({ 'email' => 'alice@example.com' })
    end

    it 'preserves acquisition_protocol and certifier_url' do
      _m, a, = request_roundtrip(:acquire_certificate, args)
      expect(a[:acquisition_protocol]).to eq('issuance')
      expect(a[:certifier_url]).to eq('https://certifier.example.com')
    end
  end

  describe 'acquireCertificate (17) — direct protocol' do
    let(:args) do
      {
        type: CERT_TYPE,
        certifier: pubkey_hex,
        fields: {},
        privileged: nil,
        privileged_reason: nil,
        acquisition_protocol: 'direct',
        serial_number: SERIAL_NUM,
        revocation_outpoint: OUTPOINT,
        signature: SIG_HEX,
        keyring_revealer: 'certifier',
        keyring_for_subject: {}
      }
    end

    it 'preserves direct protocol params' do
      _m, a, = request_roundtrip(:acquire_certificate, args)
      expect(a[:acquisition_protocol]).to eq('direct')
      expect(a[:serial_number]).to eq(SERIAL_NUM)
      expect(a[:revocation_outpoint]).to eq(OUTPOINT)
      expect(a[:keyring_revealer]).to eq('certifier')
    end
  end

  describe 'listCertificates (18)' do
    let(:args) do
      {
        certifiers: [pubkey_hex],
        types: [CERT_TYPE],
        limit: 5,
        offset: nil,
        privileged: false,
        privileged_reason: nil
      }
    end

    it 'round-trips the method' do
      m, _a, = request_roundtrip(:list_certificates, args)
      expect(m).to eq(:list_certificates)
    end

    it 'preserves certifiers and types' do
      _m, a, = request_roundtrip(:list_certificates, args)
      expect(a[:certifiers]).to eq([pubkey_hex])
      expect(a[:types]).to eq([CERT_TYPE])
    end

    it 'preserves limit and nil offset' do
      _m, a, = request_roundtrip(:list_certificates, args)
      expect(a[:limit]).to eq(5)
      expect(a[:offset]).to be_nil
    end
  end

  describe 'proveCertificate (19)' do
    let(:verifier_key) { BSV::Primitives::PrivateKey.generate.public_key.to_hex }
    let(:args) do
      {
        certificate: cert_fixture,
        fields_to_reveal: ['name'],
        verifier: verifier_key,
        privileged: nil,
        privileged_reason: nil
      }
    end

    it 'round-trips the method' do
      m, _a, = request_roundtrip(:prove_certificate, args)
      expect(m).to eq(:prove_certificate)
    end

    it 'preserves fields_to_reveal and verifier' do
      _m, a, = request_roundtrip(:prove_certificate, args)
      expect(a[:fields_to_reveal]).to eq(['name'])
      expect(a[:verifier]).to eq(verifier_key)
    end

    it 'preserves certificate core fields' do
      _m, a, = request_roundtrip(:prove_certificate, args)
      expect(a[:certificate][:type]).to eq(CERT_TYPE)
      expect(a[:certificate][:subject]).to eq(pubkey_hex)
    end
  end

  describe 'relinquishCertificate (20)' do
    let(:args) do
      {
        type: CERT_TYPE,
        serial_number: SERIAL_NUM,
        certifier: pubkey_hex
      }
    end

    it 'round-trips the method' do
      m, _a, = request_roundtrip(:relinquish_certificate, args)
      expect(m).to eq(:relinquish_certificate)
    end

    it 'preserves type, serial_number, and certifier' do
      _m, a, = request_roundtrip(:relinquish_certificate, args)
      expect(a[:type]).to eq(CERT_TYPE)
      expect(a[:serial_number]).to eq(SERIAL_NUM)
      expect(a[:certifier]).to eq(pubkey_hex)
    end
  end

  # -------------------------------------------------------------------------
  # Discovery methods (21-22)
  # -------------------------------------------------------------------------

  describe 'discoverByIdentityKey (21)' do
    let(:args) do
      {
        identity_key: pubkey_hex,
        limit: nil,
        offset: nil,
        seek_permission: nil
      }
    end

    it 'round-trips the method' do
      m, _a, = request_roundtrip(:discover_by_identity_key, args)
      expect(m).to eq(:discover_by_identity_key)
    end

    it 'preserves identity_key' do
      _m, a, = request_roundtrip(:discover_by_identity_key, args)
      expect(a[:identity_key]).to eq(pubkey_hex)
    end

    it 'preserves nil limit and offset' do
      _m, a, = request_roundtrip(:discover_by_identity_key, args)
      expect(a[:limit]).to be_nil
      expect(a[:offset]).to be_nil
    end
  end

  describe 'discoverByAttributes (22)' do
    let(:args) do
      {
        attributes: { 'name' => 'Alice', 'country' => 'AU' },
        limit: 10,
        offset: 0,
        seek_permission: true
      }
    end

    it 'round-trips the method' do
      m, _a, = request_roundtrip(:discover_by_attributes, args)
      expect(m).to eq(:discover_by_attributes)
    end

    it 'preserves attributes map' do
      _m, a, = request_roundtrip(:discover_by_attributes, args)
      expect(a[:attributes]).to eq({ 'name' => 'Alice', 'country' => 'AU' })
    end

    it 'preserves limit, offset, seek_permission' do
      _m, a, = request_roundtrip(:discover_by_attributes, args)
      expect(a[:limit]).to eq(10)
      expect(a[:offset]).to eq(0)
      expect(a[:seek_permission]).to be(true)
    end
  end

  # -------------------------------------------------------------------------
  # Auth methods (23-24)
  # -------------------------------------------------------------------------

  describe 'isAuthenticated (23)' do
    it 'round-trips the method with empty params' do
      m, a, = request_roundtrip(:is_authenticated, {})
      expect(m).to eq(:is_authenticated)
      expect(a).to eq({})
    end

    it 'round-trips response: authenticated = true' do
      data = described_class.serialize_response(:is_authenticated, { authenticated: true })
      out = described_class.deserialize_response(:is_authenticated, data)
      expect(out[:authenticated]).to be(true)
    end

    it 'round-trips response: authenticated = false' do
      data = described_class.serialize_response(:is_authenticated, { authenticated: false })
      out = described_class.deserialize_response(:is_authenticated, data)
      expect(out[:authenticated]).to be(false)
    end
  end

  describe 'waitForAuthentication (24)' do
    it 'round-trips the method with empty params' do
      m, a, = request_roundtrip(:wait_for_authentication, {})
      expect(m).to eq(:wait_for_authentication)
      expect(a).to eq({})
    end
  end

  # -------------------------------------------------------------------------
  # Blockchain methods (25-28)
  # -------------------------------------------------------------------------

  describe 'getHeight (25)' do
    it 'round-trips the method with empty params' do
      m, a, = request_roundtrip(:get_height, {})
      expect(m).to eq(:get_height)
      expect(a).to eq({})
    end

    it 'round-trips response with block height' do
      data = described_class.serialize_response(:get_height, { height: 900_000 })
      out = described_class.deserialize_response(:get_height, data)
      expect(out[:height]).to eq(900_000)
    end
  end

  describe 'getHeaderForHeight (26)' do
    let(:header_hex) { 'deadbeef' * 20 } # 80 bytes
    let(:args) { { height: 830_000 } }

    it 'round-trips the method' do
      m, _a, = request_roundtrip(:get_header_for_height, args)
      expect(m).to eq(:get_header_for_height)
    end

    it 'preserves height' do
      _m, a, = request_roundtrip(:get_header_for_height, args)
      expect(a[:height]).to eq(830_000)
    end

    it 'round-trips response with header hex' do
      data = described_class.serialize_response(:get_header_for_height, { header: header_hex })
      out = described_class.deserialize_response(:get_header_for_height, data)
      expect(out[:header]).to eq(header_hex)
    end
  end

  describe 'getNetwork (27)' do
    it 'round-trips the method with empty params' do
      m, a, = request_roundtrip(:get_network, {})
      expect(m).to eq(:get_network)
      expect(a).to eq({})
    end

    it 'round-trips response: mainnet' do
      data = described_class.serialize_response(:get_network, { network: 'mainnet' })
      out = described_class.deserialize_response(:get_network, data)
      expect(out[:network]).to eq('mainnet')
    end

    it 'round-trips response: testnet' do
      data = described_class.serialize_response(:get_network, { network: 'testnet' })
      out = described_class.deserialize_response(:get_network, data)
      expect(out[:network]).to eq('testnet')
    end
  end

  describe 'getVersion (28)' do
    it 'round-trips the method with empty params' do
      m, a, = request_roundtrip(:get_version, {})
      expect(m).to eq(:get_version)
      expect(a).to eq({})
    end

    it 'round-trips response with version string' do
      data = described_class.serialize_response(:get_version, { version: '0.3.1' })
      out = described_class.deserialize_response(:get_version, data)
      expect(out[:version]).to eq('0.3.1')
    end
  end

  # -------------------------------------------------------------------------
  # All 28 call codes exist and are symmetrical
  # -------------------------------------------------------------------------

  describe 'CALL_CODES / METHODS_BY_CODE' do
    it 'defines exactly 28 methods' do
      expect(BSV::Wallet::Wire::Serializer::CALL_CODES.length).to eq(28)
    end

    it 'has a unique code for every method' do
      codes = BSV::Wallet::Wire::Serializer::CALL_CODES.values
      expect(codes.uniq.length).to eq(28)
    end

    it 'covers codes 1 through 28 with no gaps' do
      codes = BSV::Wallet::Wire::Serializer::CALL_CODES.values.sort
      expect(codes).to eq((1..28).to_a)
    end

    it 'METHODS_BY_CODE is the exact inverse of CALL_CODES' do
      BSV::Wallet::Wire::Serializer::CALL_CODES.each do |method, code|
        expect(BSV::Wallet::Wire::Serializer::METHODS_BY_CODE[code]).to eq(method)
      end
    end
  end
end
