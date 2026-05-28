# frozen_string_literal: true

# ---- Shared test data (mirrors go-sdk vector_test.go) ----
BRC103_TESTDATA_DIR    = '/opt/ruby/bsv-reference-sdks/go-sdk/wallet/substrates/testdata'
BRC103_PUB_KEY_HEX     = '025ad43a22ac38d0bc1f8bacaabb323b5d634703b7a774c4268f6a09e4ddf79097'
BRC103_COUNTERPARTY_HEX = '0294c479f762f6baa97fbcd4393564c1d7bd8336ebd15928135bbcf575cd1a71a1'
BRC103_VERIFIER_HEX    = '03b106dae20ae8fca0f4e8983d974c4b583054573eecdcdcfad261c035415ce1ee'
BRC103_PROVER_HEX      = '02e14bb4fbcd33d02a0bad2b60dcd14c36506fa15599e3c28ec87eff440a97a2b8'
BRC103_CERTIFIER_HEX   = '0294c479f762f6baa97fbcd4393564c1d7bd8336ebd15928135bbcf575cd1a71a1'
BRC103_TXID_HEX        = '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
BRC103_OUTPOINT_STR    = 'aec245f27b7640c8b1865045107731bfb848115c573f7da38166074b1c9e475d.0'
BRC103_TYPE_B64        = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB0ZXN0LXR5cGU='
BRC103_SERIAL_B64      = 'AAAAAAAAAAAAAAAAAAB0ZXN0LXNlcmlhbC1udW1iZXI='
BRC103_SIG_HEX         = '3045022100a6f09ee70382ab364f3f6b040aebb8fe7a51dbc3b4c99cfeb2f7756432162833022067349b91a6319345996faddf36d1b2f3a502e4ae002205f9d2db85474f9aed5a'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'BRC-103 cross-SDK wire conformance (go-sdk vectors)' do
  # rubocop:enable RSpec/DescribeClass

  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    skip 'Go SDK reference testdata not present — clone bsv-reference-sdks to run conformance specs' unless File.directory?(BRC103_TESTDATA_DIR)
  end

  def go_wire(name)
    JSON.parse(File.read("#{BRC103_TESTDATA_DIR}/#{name}.json"))['wire']
  end

  def hex(s)
    [s].pack('H*').b
  end

  def b64(s)
    Base64.decode64(s).b
  end

  def frame_req(call, payload)
    BSV::Wallet::Wire::Frame.write_request(call: call, originator: '', params: payload)
  end

  def frame_res(payload)
    BSV::Wallet::Wire::Frame.write_result(payload: payload)
  end

  let(:locking_script) { hex('76a9143cf53c49c322d9d811728182939aee2dca087f9888ac') }
  let(:short_sig)      { hex('302502204e45e16932b8af514961a1d3a1a25fdf3f4f7732e9d624c6c61548ab5fb8cd41020101') }
  let(:test_protocol)  { [1, 'test-protocol'] }
  let(:test_key_id)    { 'test-key' }

  # Shared certificate hash used across multiple test cases (base64/hex API).
  let(:base_cert) do
    {
      type: BRC103_TYPE_B64,
      serial_number: BRC103_SERIAL_B64,
      subject: BRC103_PUB_KEY_HEX,
      certifier: BRC103_CERTIFIER_HEX,
      revocation_outpoint: BRC103_OUTPOINT_STR,
      fields: { 'email' => 'alice@example.com', 'name' => 'Alice' },
      signature: BRC103_SIG_HEX
    }
  end

  # Helper: shared identity certificate for discover_* results.
  let(:identity_cert) do
    base_cert.merge(
      certifier_info: {
        name: 'Test Certifier',
        icon_url: 'https://example.com/icon.png',
        description: 'Certifier description',
        trust: 5
      },
      publicly_revealed_keyring: { 'pubField' => 'AlrUOiKsONC8H4usqrsyO11jRwO3p3TEJo9qCeTd95CX' },
      decrypted_fields: { 'name' => 'Alice' }
    )
  end

  shared_examples 'matches go wire' do |fixture_name|
    it "matches #{fixture_name}" do
      expect(subject.unpack1('H*')).to eq(go_wire(fixture_name))
    end
  end

  # ---- createAction ----
  describe 'createAction args' do
    subject do
      args = {
        description: 'Test action description',
        input_beef: nil,
        inputs: nil,
        outputs: [
          {
            locking_script: locking_script,
            satoshis: 999,
            output_description: 'Test output',
            basket: 'test-basket',
            custom_instructions: 'Test instructions',
            tags: ['test-tag']
          }
        ],
        lock_time: nil,
        version: nil,
        labels: ['test-label'],
        options: nil
      }
      frame_req(BSV::Wallet::Wire::Calls::CREATE_ACTION, BSV::Wallet::Serializer::CreateActionArgs.serialize(args))
    end

    it_behaves_like 'matches go wire', 'createAction-1-out-args'
  end

  # ---- abortAction ----
  describe 'abortAction args' do
    subject { frame_req(BSV::Wallet::Wire::Calls::ABORT_ACTION, BSV::Wallet::Serializer::AbortAction.serialize_args(reference: b64('dGVzdA=='))) }

    it_behaves_like 'matches go wire', 'abortAction-simple-args'
  end

  describe 'abortAction result' do
    subject { frame_res(BSV::Wallet::Serializer::AbortAction.serialize_result(aborted: true)) }

    it_behaves_like 'matches go wire', 'abortAction-simple-result'
  end

  # ---- signAction ----
  describe 'signAction args' do
    subject do
      args = {
        reference: b64('dGVzdA=='),
        spends: {
          0 => {
            unlocking_script: hex('76a91489abcdefabbaabbaabbaabbaabbaabbaabbaabba88ac'),
            sequence_number: nil
          }
        }
      }
      frame_req(BSV::Wallet::Wire::Calls::SIGN_ACTION, BSV::Wallet::Serializer::SignActionArgs.serialize(args))
    end

    it_behaves_like 'matches go wire', 'signAction-simple-args'
  end

  # ---- listActions ----
  describe 'listActions args' do
    subject do
      args = {
        labels: ['test-label'],
        label_query_mode: nil,
        include_labels: nil,
        include_inputs: nil,
        include_input_source_locking_scripts: nil,
        include_input_unlocking_scripts: nil,
        include_outputs: true,
        include_output_locking_scripts: nil,
        limit: 10,
        offset: nil,
        seek_permission: nil
      }
      frame_req(BSV::Wallet::Wire::Calls::LIST_ACTIONS, BSV::Wallet::Serializer::ListActionsArgs.serialize(args))
    end

    it_behaves_like 'matches go wire', 'listActions-simple-args'
  end

  describe 'listActions result' do
    subject do
      result = {
        total_actions: 1,
        actions: [
          {
            txid: BRC103_TXID_HEX,
            satoshis: 1000,
            status: :completed,
            is_outgoing: true,
            description: 'Test transaction 1',
            labels: nil,
            version: 1,
            lock_time: 10,
            inputs: nil,
            outputs: [
              {
                output_index: 1,
                satoshis: 1000,
                locking_script: locking_script,
                spendable: true,
                output_description: 'Test output',
                basket: 'basket1',
                tags: %w[tag1 tag2],
                custom_instructions: nil
              }
            ]
          }
        ]
      }
      frame_res(BSV::Wallet::Serializer::ListActionsResult.serialize(result))
    end

    it_behaves_like 'matches go wire', 'listActions-simple-result'
  end

  # ---- internalizeAction ----
  describe 'internalizeAction args' do
    subject do
      args = {
        tx: "\x01\x02\x03\x04".b,
        description: 'test transaction',
        labels: %w[label1 label2],
        seek_permission: true,
        outputs: [
          {
            output_index: 0,
            protocol: :wallet_payment,
            payment_remittance: {
              derivation_prefix: b64('cHJlZml4'),
              derivation_suffix: b64('c3VmZml4'),
              sender_identity_key: BRC103_VERIFIER_HEX
            }
          },
          {
            output_index: 1,
            protocol: :basket_insertion,
            insertion_remittance: {
              basket: 'test-basket',
              custom_instructions: 'instruction',
              tags: %w[tag1 tag2]
            }
          }
        ]
      }
      frame_req(BSV::Wallet::Wire::Calls::INTERNALIZE_ACTION, BSV::Wallet::Serializer::InternalizeActionArgs.serialize(args))
    end

    it_behaves_like 'matches go wire', 'internalizeAction-simple-args'
  end

  describe 'internalizeAction result' do
    subject { frame_res(BSV::Wallet::Serializer::InternalizeActionResult.serialize(accepted: true)) }

    it_behaves_like 'matches go wire', 'internalizeAction-simple-result'
  end

  # ---- listOutputs ----
  describe 'listOutputs args' do
    subject do
      args = {
        basket: 'test-basket',
        tags: %w[tag1 tag2],
        tag_query_mode: :any,
        include: :locking_scripts,
        include_custom_instructions: nil,
        include_tags: true,
        include_labels: nil,
        limit: 10,
        offset: nil,
        seek_permission: nil
      }
      frame_req(BSV::Wallet::Wire::Calls::LIST_OUTPUTS, BSV::Wallet::Serializer::ListOutputs.serialize_args(args))
    end

    it_behaves_like 'matches go wire', 'listOutputs-simple-args'
  end

  describe 'listOutputs result' do
    subject do
      result = {
        total_outputs: 2,
        beef: "\x01\x02\x03\x04".b,
        outputs: [
          { outpoint: "#{BRC103_TXID_HEX}.0", satoshis: 1000, locking_script: nil, custom_instructions: nil, tags: nil, labels: nil },
          { outpoint: 'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890.2', satoshis: 5000, locking_script: nil, custom_instructions: nil, tags: nil, labels: nil }
        ]
      }
      frame_res(BSV::Wallet::Serializer::ListOutputs.serialize_result(result))
    end

    it_behaves_like 'matches go wire', 'listOutputs-simple-result'
  end

  # ---- relinquishOutput ----
  describe 'relinquishOutput args' do
    subject do
      args = { output: 'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890.2', basket: 'test-basket' }
      frame_req(BSV::Wallet::Wire::Calls::RELINQUISH_OUTPUT, BSV::Wallet::Serializer::RelinquishOutput.serialize_args(args))
    end

    it_behaves_like 'matches go wire', 'relinquishOutput-simple-args'
  end

  describe 'relinquishOutput result' do
    subject { frame_res(BSV::Wallet::Serializer::RelinquishOutput.serialize_result(relinquished: true)) }

    it_behaves_like 'matches go wire', 'relinquishOutput-simple-result'
  end

  # ---- getPublicKey ----
  describe 'getPublicKey args' do
    subject do
      args = {
        identity_key: false,
        protocol_id: [2, 'tests'],
        key_id: 'test-key-id',
        counterparty: BRC103_COUNTERPARTY_HEX,
        privileged: true,
        privileged_reason: 'privileged reason',
        for_self: nil,
        seek_permission: true
      }
      frame_req(BSV::Wallet::Wire::Calls::GET_PUBLIC_KEY, BSV::Wallet::Serializer::GetPublicKey::Args.serialize(args))
    end

    it_behaves_like 'matches go wire', 'getPublicKey-simple-args'
  end

  describe 'getPublicKey result' do
    subject { frame_res(BSV::Wallet::Serializer::GetPublicKey::Result.serialize(public_key: hex(BRC103_PUB_KEY_HEX))) }

    it_behaves_like 'matches go wire', 'getPublicKey-simple-result'
  end

  # ---- revealCounterpartyKeyLinkage ----
  describe 'revealCounterpartyKeyLinkage args' do
    subject do
      args = { counterparty: BRC103_COUNTERPARTY_HEX, verifier: BRC103_VERIFIER_HEX, privileged: true, privileged_reason: 'test-reason' }
      frame_req(BSV::Wallet::Wire::Calls::REVEAL_COUNTERPARTY_KEY_LINKAGE, BSV::Wallet::Serializer::RevealCounterpartyKeyLinkage::Args.serialize(args))
    end

    it_behaves_like 'matches go wire', 'revealCounterpartyKeyLinkage-simple-args'
  end

  describe 'revealCounterpartyKeyLinkage result' do
    subject do
      result = {
        prover: hex(BRC103_PROVER_HEX),
        verifier: hex(BRC103_VERIFIER_HEX),
        counterparty: hex(BRC103_COUNTERPARTY_HEX),
        revelation_time: '2023-01-01T00:00:00Z',
        encrypted_linkage: [1, 2, 3, 4],
        encrypted_linkage_proof: [5, 6, 7, 8]
      }
      frame_res(BSV::Wallet::Serializer::RevealCounterpartyKeyLinkage::Result.serialize(result))
    end

    it_behaves_like 'matches go wire', 'revealCounterpartyKeyLinkage-simple-result'
  end

  # ---- revealSpecificKeyLinkage ----
  describe 'revealSpecificKeyLinkage args' do
    subject do
      args = {
        protocol_id: [2, 'tests'],
        key_id: 'test-key-id',
        counterparty: BRC103_COUNTERPARTY_HEX,
        verifier: BRC103_VERIFIER_HEX,
        privileged: true,
        privileged_reason: 'test-reason'
      }
      frame_req(BSV::Wallet::Wire::Calls::REVEAL_SPECIFIC_KEY_LINKAGE, BSV::Wallet::Serializer::RevealSpecificKeyLinkage::Args.serialize(args))
    end

    it_behaves_like 'matches go wire', 'revealSpecificKeyLinkage-simple-args'
  end

  describe 'revealSpecificKeyLinkage result' do
    subject do
      result = {
        prover: hex(BRC103_PROVER_HEX),
        verifier: hex(BRC103_VERIFIER_HEX),
        counterparty: hex(BRC103_COUNTERPARTY_HEX),
        protocol_id: [2, 'tests'],
        key_id: 'test-key-id',
        encrypted_linkage: [1, 2, 3, 4],
        encrypted_linkage_proof: [5, 6, 7, 8],
        proof_type: 1
      }
      frame_res(BSV::Wallet::Serializer::RevealSpecificKeyLinkage::Result.serialize(result))
    end

    it_behaves_like 'matches go wire', 'revealSpecificKeyLinkage-simple-result'
  end

  # ---- encrypt ----
  describe 'encrypt args' do
    subject do
      args = {
        protocol_id: test_protocol, key_id: test_key_id, counterparty: 'self',
        privileged: true, privileged_reason: 'test reason', seek_permission: true,
        plaintext: [1, 2, 3, 4]
      }
      frame_req(BSV::Wallet::Wire::Calls::ENCRYPT, BSV::Wallet::Serializer::Encrypt::Args.serialize(args))
    end

    it_behaves_like 'matches go wire', 'encrypt-simple-args'
  end

  describe 'encrypt result' do
    subject { frame_res(BSV::Wallet::Serializer::Encrypt::Result.serialize(ciphertext: [1, 2, 3, 4, 5, 6, 7, 8])) }

    it_behaves_like 'matches go wire', 'encrypt-simple-result'
  end

  # ---- decrypt ----
  describe 'decrypt args' do
    subject do
      args = {
        protocol_id: test_protocol, key_id: test_key_id, counterparty: 'self',
        privileged: true, privileged_reason: 'test reason', seek_permission: true,
        ciphertext: [1, 2, 3, 4, 5, 6, 7, 8]
      }
      frame_req(BSV::Wallet::Wire::Calls::DECRYPT, BSV::Wallet::Serializer::Decrypt::Args.serialize(args))
    end

    it_behaves_like 'matches go wire', 'decrypt-simple-args'
  end

  describe 'decrypt result' do
    subject { frame_res(BSV::Wallet::Serializer::Decrypt::Result.serialize(plaintext: [1, 2, 3, 4])) }

    it_behaves_like 'matches go wire', 'decrypt-simple-result'
  end

  # ---- createHmac ----
  describe 'createHmac args' do
    subject do
      args = {
        protocol_id: test_protocol, key_id: test_key_id, counterparty: 'self',
        privileged: true, privileged_reason: 'test reason', seek_permission: true,
        data: [10, 20, 30, 40]
      }
      frame_req(BSV::Wallet::Wire::Calls::CREATE_HMAC, BSV::Wallet::Serializer::CreateHmac::Args.serialize(args))
    end

    it_behaves_like 'matches go wire', 'createHmac-simple-args'
  end

  describe 'createHmac result' do
    subject { frame_res(BSV::Wallet::Serializer::CreateHmac::Result.serialize(hmac: hmac_arr)) }

    let(:hmac_arr) { [50, 60, 70, 80, 90, 100, 110, 120] * 4 }

    it_behaves_like 'matches go wire', 'createHmac-simple-result'
  end

  # ---- verifyHmac ----
  describe 'verifyHmac args' do
    subject do
      args = {
        protocol_id: test_protocol, key_id: test_key_id, counterparty: 'self',
        privileged: true, privileged_reason: 'test reason', seek_permission: true,
        data: [10, 20, 30, 40], hmac: hmac_arr
      }
      frame_req(BSV::Wallet::Wire::Calls::VERIFY_HMAC, BSV::Wallet::Serializer::VerifyHmac::Args.serialize(args))
    end

    let(:hmac_arr) { [50, 60, 70, 80, 90, 100, 110, 120] * 4 }

    it_behaves_like 'matches go wire', 'verifyHmac-simple-args'
  end

  describe 'verifyHmac result' do
    subject { frame_res(BSV::Wallet::Serializer::VerifyHmac::Result.serialize(valid: true)) }

    it_behaves_like 'matches go wire', 'verifyHmac-simple-result'
  end

  # ---- createSignature ----
  describe 'createSignature args' do
    subject do
      args = {
        protocol_id: test_protocol, key_id: test_key_id, counterparty: 'self',
        privileged: true, privileged_reason: 'test reason', seek_permission: true,
        data: [11, 22, 33, 44]
      }
      frame_req(BSV::Wallet::Wire::Calls::CREATE_SIGNATURE, BSV::Wallet::Serializer::CreateSignature::Args.serialize(args))
    end

    it_behaves_like 'matches go wire', 'createSignature-simple-args'
  end

  describe 'createSignature result' do
    subject { frame_res(BSV::Wallet::Serializer::CreateSignature::Result.serialize(signature: short_sig)) }

    it_behaves_like 'matches go wire', 'createSignature-simple-result'
  end

  # ---- verifySignature ----
  describe 'verifySignature args' do
    subject do
      args = {
        protocol_id: test_protocol, key_id: test_key_id, counterparty: 'self',
        privileged: true, privileged_reason: 'test reason', seek_permission: true,
        data: [11, 22, 33, 44], signature: short_sig
      }
      frame_req(BSV::Wallet::Wire::Calls::VERIFY_SIGNATURE, BSV::Wallet::Serializer::VerifySignature::Args.serialize(args))
    end

    it_behaves_like 'matches go wire', 'verifySignature-simple-args'
  end

  describe 'verifySignature result' do
    subject { frame_res(BSV::Wallet::Serializer::VerifySignature::Result.serialize(valid: true)) }

    it_behaves_like 'matches go wire', 'verifySignature-simple-result'
  end

  # ---- acquireCertificate ----
  describe 'acquireCertificate args (direct)' do
    subject do
      args = {
        type: BRC103_TYPE_B64, certifier: BRC103_CERTIFIER_HEX, acquisition_protocol: :direct,
        fields: { 'email' => 'alice@example.com', 'name' => 'Alice' },
        serial_number: BRC103_SERIAL_B64, revocation_outpoint: BRC103_OUTPOINT_STR,
        signature: BRC103_SIG_HEX, keyring_revealer: BRC103_PUB_KEY_HEX,
        keyring_for_subject: { 'field1' => 'key1', 'field2' => 'key2' },
        privileged: false
      }
      frame_req(BSV::Wallet::Wire::Calls::ACQUIRE_CERTIFICATE, BSV::Wallet::Serializer::AcquireCertificate.serialize_args(args))
    end

    it_behaves_like 'matches go wire', 'acquireCertificate-simple-args'
  end

  describe 'acquireCertificate args (issuance)' do
    subject do
      args = {
        type: BRC103_TYPE_B64, certifier: BRC103_CERTIFIER_HEX, acquisition_protocol: :issuance,
        fields: { 'email' => 'alice@example.com', 'name' => 'Alice' },
        certifier_url: 'https://certifier.example.com', privileged: false
      }
      frame_req(BSV::Wallet::Wire::Calls::ACQUIRE_CERTIFICATE, BSV::Wallet::Serializer::AcquireCertificate.serialize_args(args))
    end

    it_behaves_like 'matches go wire', 'acquireCertificate-issuance-args'
  end

  describe 'acquireCertificate result' do
    subject { frame_res(BSV::Wallet::Serializer::AcquireCertificate.serialize_result(base_cert)) }

    it_behaves_like 'matches go wire', 'acquireCertificate-simple-result'
  end

  # ---- listCertificates ----
  describe 'listCertificates args' do
    subject do
      args = {
        certifiers: [BRC103_CERTIFIER_HEX, BRC103_VERIFIER_HEX],
        types: ['dGVzdC10eXBlMSAgICAgICAgICAgICAgICAgICAgICA=', 'dGVzdC10eXBlMiAgICAgICAgICAgICAgICAgICAgICA='],
        limit: 5, offset: 0, privileged: true, privileged_reason: 'list-cert-reason'
      }
      frame_req(BSV::Wallet::Wire::Calls::LIST_CERTIFICATES, BSV::Wallet::Serializer::ListCertificates.serialize_args(args))
    end

    it_behaves_like 'matches go wire', 'listCertificates-simple-args'
  end

  describe 'listCertificates result (simple)' do
    subject do
      result = { total_certificates: 1, certificates: [base_cert] }
      frame_res(BSV::Wallet::Serializer::ListCertificates.serialize_result(result))
    end

    it_behaves_like 'matches go wire', 'listCertificates-simple-result'
  end

  describe 'listCertificates result (full — with keyring and verifier)' do
    subject do
      cert_full = base_cert.merge(
        keyring: { 'field1' => 'a2V5MQ==', 'field2' => 'a2V5Mg==' },
        verifier: hex(BRC103_VERIFIER_HEX)
      )
      result = { total_certificates: 1, certificates: [cert_full] }
      frame_res(BSV::Wallet::Serializer::ListCertificates.serialize_result(result))
    end

    it_behaves_like 'matches go wire', 'listCertificates-full-result'
  end

  # ---- proveCertificate ----
  describe 'proveCertificate args' do
    subject do
      args = {
        certificate: base_cert.merge(fields: { 'email' => 'alice@example.com', 'name' => 'Alice' }),
        fields_to_reveal: ['name'],
        verifier: BRC103_VERIFIER_HEX,
        privileged: false,
        privileged_reason: 'prove-reason'
      }
      frame_req(BSV::Wallet::Wire::Calls::PROVE_CERTIFICATE, BSV::Wallet::Serializer::ProveCertificate.serialize_args(args))
    end

    it_behaves_like 'matches go wire', 'proveCertificate-simple-args'
  end

  describe 'proveCertificate result' do
    subject { frame_res(BSV::Wallet::Serializer::ProveCertificate.serialize_result(keyring_for_verifier: { 'name' => 'bmFtZS1rZXk=' })) }

    it_behaves_like 'matches go wire', 'proveCertificate-simple-result'
  end

  # ---- relinquishCertificate ----
  describe 'relinquishCertificate args' do
    subject do
      args = { type: BRC103_TYPE_B64, serial_number: BRC103_SERIAL_B64, certifier: BRC103_CERTIFIER_HEX }
      frame_req(BSV::Wallet::Wire::Calls::RELINQUISH_CERTIFICATE, BSV::Wallet::Serializer::RelinquishCertificate.serialize_args(args))
    end

    it_behaves_like 'matches go wire', 'relinquishCertificate-simple-args'
  end

  describe 'relinquishCertificate result' do
    subject { frame_res(BSV::Wallet::Serializer::RelinquishCertificate.serialize_result(relinquished: true)) }

    it_behaves_like 'matches go wire', 'relinquishCertificate-simple-result'
  end

  # ---- discoverByIdentityKey ----
  describe 'discoverByIdentityKey args' do
    subject do
      args = { identity_key: BRC103_CERTIFIER_HEX, limit: 10, offset: 0, seek_permission: true }
      frame_req(BSV::Wallet::Wire::Calls::DISCOVER_BY_IDENTITY_KEY, BSV::Wallet::Serializer::DiscoverByIdentityKey.serialize_args(args))
    end

    it_behaves_like 'matches go wire', 'discoverByIdentityKey-simple-args'
  end

  describe 'discoverByIdentityKey result' do
    subject do
      result = { total_certificates: 1, certificates: [identity_cert] }
      frame_res(BSV::Wallet::Serializer::DiscoverByIdentityKey.serialize_result(result))
    end

    it_behaves_like 'matches go wire', 'discoverByIdentityKey-simple-result'
  end

  # ---- discoverByAttributes ----
  describe 'discoverByAttributes args' do
    subject do
      args = { attributes: { 'email' => 'alice@example.com', 'role' => 'admin' }, limit: 5, offset: 0, seek_permission: false }
      frame_req(BSV::Wallet::Wire::Calls::DISCOVER_BY_ATTRIBUTES, BSV::Wallet::Serializer::DiscoverByAttributes.serialize_args(args))
    end

    it_behaves_like 'matches go wire', 'discoverByAttributes-simple-args'
  end

  describe 'discoverByAttributes result' do
    subject do
      result = { total_certificates: 1, certificates: [identity_cert] }
      frame_res(BSV::Wallet::Serializer::DiscoverByAttributes.serialize_result(result))
    end

    it_behaves_like 'matches go wire', 'discoverByAttributes-simple-result'
  end

  # ---- isAuthenticated ----
  describe 'isAuthenticated args' do
    subject { frame_req(BSV::Wallet::Wire::Calls::IS_AUTHENTICATED, BSV::Wallet::Serializer::IsAuthenticated::Args.serialize({})) }

    it_behaves_like 'matches go wire', 'isAuthenticated-simple-args'
  end

  describe 'isAuthenticated result' do
    subject { frame_res(BSV::Wallet::Serializer::IsAuthenticated::Result.serialize(authenticated: true)) }

    it_behaves_like 'matches go wire', 'isAuthenticated-simple-result'
  end

  # ---- waitForAuthentication ----
  describe 'waitForAuthentication args' do
    subject { frame_req(BSV::Wallet::Wire::Calls::WAIT_FOR_AUTHENTICATION, BSV::Wallet::Serializer::WaitForAuthentication::Args.serialize({})) }

    it_behaves_like 'matches go wire', 'waitForAuthentication-simple-args'
  end

  describe 'waitForAuthentication result' do
    subject { frame_res(BSV::Wallet::Serializer::WaitForAuthentication::Result.serialize(authenticated: true)) }

    it_behaves_like 'matches go wire', 'waitForAuthentication-simple-result'
  end

  # ---- getHeight ----
  describe 'getHeight args' do
    subject { frame_req(BSV::Wallet::Wire::Calls::GET_HEIGHT, BSV::Wallet::Serializer::GetHeight::Args.serialize({})) }

    it_behaves_like 'matches go wire', 'getHeight-simple-args'
  end

  describe 'getHeight result' do
    subject { frame_res(BSV::Wallet::Serializer::GetHeight::Result.serialize(height: 850_000)) }

    it_behaves_like 'matches go wire', 'getHeight-simple-result'
  end

  # ---- getHeaderForHeight ----
  describe 'getHeaderForHeight args' do
    subject { frame_req(BSV::Wallet::Wire::Calls::GET_HEADER_FOR_HEIGHT, BSV::Wallet::Serializer::GetHeaderForHeight::Args.serialize(height: 850_000)) }

    it_behaves_like 'matches go wire', 'getHeaderForHeight-simple-args'
  end

  describe 'getHeaderForHeight result' do
    subject { frame_res(BSV::Wallet::Serializer::GetHeaderForHeight::Result.serialize(header: genesis_header)) }

    let(:genesis_header) do
      hex('0100000000000000000000000000000000000000000000000000000000000000000000003ba3edfd7a7b12b27ac72c3e67768f617fc81bc3888a51323a9fb8aa4b1e5e4a29ab5f49ffff001d1dac2b7c')
    end

    it_behaves_like 'matches go wire', 'getHeaderForHeight-simple-result'
  end

  # ---- getNetwork ----
  describe 'getNetwork result' do
    subject { frame_res(BSV::Wallet::Serializer::GetNetwork::Result.serialize(network: 'mainnet')) }

    it_behaves_like 'matches go wire', 'getNetwork-simple-result'
  end

  # ---- getVersion ----
  describe 'getVersion result' do
    subject { frame_res(BSV::Wallet::Serializer::GetVersion::Result.serialize(version: '1.0.0')) }

    it_behaves_like 'matches go wire', 'getVersion-simple-result'
  end
end
