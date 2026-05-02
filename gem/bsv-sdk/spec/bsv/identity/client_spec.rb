# frozen_string_literal: true

require 'spec_helper'

# Constants used across the describe blocks — defined at spec-file scope
# to avoid Lint/ConstantDefinitionInBlock.
IDENTITY_CLIENT_SPEC_PUBKEY = "02#{'ab' * 32}"
IDENTITY_CLIENT_SPEC_CERTIFIER = "03#{'cd' * 32}"

RSpec.describe 'BSV::Identity::Client' do
  subject(:client) { described_class.new(wallet: wallet) }

  let(:described_class) { BSV::Identity::Client }
  # Use a plain double — the wallet is duck-typed and Interface is not loaded by default.
  let(:wallet) { double('wallet') } # rubocop:disable RSpec/VerifiedDoubles

  # Minimal certificate hash as returned by the wallet's discover methods.
  def raw_cert(
    type_key: :email_cert,
    subject: IDENTITY_CLIENT_SPEC_PUBKEY,
    decrypted_fields: { 'email' => 'alice@example.com' },
    certifier_info: { name: 'TrustCo', icon_url: 'https://tc.example.com/icon.png' }
  )
    {
      type: BSV::Identity::Constants::KNOWN_IDENTITY_TYPES[type_key],
      subject: subject,
      fields: { 'email' => 'encrypted_value' },
      serial_number: 'AAABBBCCC==',
      certifier: IDENTITY_CLIENT_SPEC_CERTIFIER,
      decrypted_fields: decrypted_fields,
      certifier_info: certifier_info
    }
  end

  # ---------------------------------------------------------------------------
  # Part 1 — Resolution methods
  # ---------------------------------------------------------------------------

  describe '#resolve_by_identity_key' do
    context 'with one matching certificate' do
      before do
        allow(wallet).to receive(:discover_by_identity_key)
          .with(identity_key: IDENTITY_CLIENT_SPEC_PUBKEY, originator: nil)
          .and_return({ total_certificates: 1, certificates: [raw_cert] })
      end

      it 'returns an array of DisplayableIdentity' do
        results = client.resolve_by_identity_key(identity_key: IDENTITY_CLIENT_SPEC_PUBKEY)
        expect(results).to all(be_a(BSV::Identity::DisplayableIdentity))
      end

      it 'parses the email from the certificate' do
        result = client.resolve_by_identity_key(identity_key: IDENTITY_CLIENT_SPEC_PUBKEY).first
        expect(result.name).to eq('alice@example.com')
      end

      it 'sets identity_key from the subject field' do
        result = client.resolve_by_identity_key(identity_key: IDENTITY_CLIENT_SPEC_PUBKEY).first
        expect(result.identity_key).to eq(IDENTITY_CLIENT_SPEC_PUBKEY)
      end
    end

    context 'with multiple certificates' do
      let(:email_cert)   { raw_cert(decrypted_fields: { 'email' => 'alice@example.com' }) }
      let(:x_cert_entry) { raw_cert(type_key: :x_cert, decrypted_fields: { 'userName' => '@alice', 'profilePhoto' => nil }) }

      before do
        allow(wallet).to receive(:discover_by_identity_key)
          .with(identity_key: IDENTITY_CLIENT_SPEC_PUBKEY, originator: nil)
          .and_return({ total_certificates: 2, certificates: [email_cert, x_cert_entry] })
      end

      it 'returns one DisplayableIdentity per certificate' do
        results = client.resolve_by_identity_key(identity_key: IDENTITY_CLIENT_SPEC_PUBKEY)
        expect(results.length).to eq(2)
      end
    end

    context 'with no results' do
      before do
        allow(wallet).to receive(:discover_by_identity_key)
          .with(identity_key: IDENTITY_CLIENT_SPEC_PUBKEY, originator: nil)
          .and_return({ total_certificates: 0, certificates: [] })
      end

      it 'returns an empty array' do
        expect(client.resolve_by_identity_key(identity_key: IDENTITY_CLIENT_SPEC_PUBKEY)).to eq([])
      end
    end

    context 'with nil result' do
      before do
        allow(wallet).to receive(:discover_by_identity_key)
          .with(identity_key: IDENTITY_CLIENT_SPEC_PUBKEY, originator: nil)
          .and_return(nil)
      end

      it 'returns an empty array' do
        expect(client.resolve_by_identity_key(identity_key: IDENTITY_CLIENT_SPEC_PUBKEY)).to eq([])
      end
    end

    context 'with limit and offset' do
      before do
        allow(wallet).to receive(:discover_by_identity_key)
          .with(identity_key: IDENTITY_CLIENT_SPEC_PUBKEY, limit: 5, offset: 10, originator: nil)
          .and_return({ total_certificates: 0, certificates: [] })
      end

      it 'passes limit and offset to the wallet' do
        client.resolve_by_identity_key(identity_key: IDENTITY_CLIENT_SPEC_PUBKEY, limit: 5, offset: 10)
        expect(wallet).to have_received(:discover_by_identity_key)
          .with(identity_key: IDENTITY_CLIENT_SPEC_PUBKEY, limit: 5, offset: 10, originator: nil)
      end
    end

    context 'with an originator' do
      subject(:client) { described_class.new(wallet: wallet, originator: 'myapp.example.com') }

      before do
        allow(wallet).to receive(:discover_by_identity_key)
          .with(identity_key: IDENTITY_CLIENT_SPEC_PUBKEY, originator: 'myapp.example.com')
          .and_return({ total_certificates: 0, certificates: [] })
      end

      it 'passes the originator through to the wallet' do
        client.resolve_by_identity_key(identity_key: IDENTITY_CLIENT_SPEC_PUBKEY)
        expect(wallet).to have_received(:discover_by_identity_key)
          .with(identity_key: IDENTITY_CLIENT_SPEC_PUBKEY, originator: 'myapp.example.com')
      end
    end
  end

  describe '#resolve_by_attributes' do
    let(:attributes) { { 'email' => 'alice@example.com' } }

    context 'with one matching certificate' do
      before do
        allow(wallet).to receive(:discover_by_attributes)
          .with(attributes: attributes, originator: nil)
          .and_return({ total_certificates: 1, certificates: [raw_cert] })
      end

      it 'returns an array of DisplayableIdentity' do
        results = client.resolve_by_attributes(attributes: attributes)
        expect(results).to all(be_a(BSV::Identity::DisplayableIdentity))
      end

      it 'parses the certificate correctly' do
        result = client.resolve_by_attributes(attributes: attributes).first
        expect(result.name).to eq('alice@example.com')
      end
    end

    context 'with no results' do
      before do
        allow(wallet).to receive(:discover_by_attributes)
          .with(attributes: attributes, originator: nil)
          .and_return({ total_certificates: 0, certificates: [] })
      end

      it 'returns an empty array' do
        expect(client.resolve_by_attributes(attributes: attributes)).to eq([])
      end
    end

    context 'with nil result' do
      before do
        allow(wallet).to receive(:discover_by_attributes)
          .with(attributes: attributes, originator: nil)
          .and_return(nil)
      end

      it 'returns an empty array' do
        expect(client.resolve_by_attributes(attributes: attributes)).to eq([])
      end
    end

    context 'with limit and offset' do
      before do
        allow(wallet).to receive(:discover_by_attributes)
          .with(attributes: attributes, limit: 3, offset: 6, originator: nil)
          .and_return({ total_certificates: 0, certificates: [] })
      end

      it 'passes limit and offset to the wallet' do
        client.resolve_by_attributes(attributes: attributes, limit: 3, offset: 6)
        expect(wallet).to have_received(:discover_by_attributes)
          .with(attributes: attributes, limit: 3, offset: 6, originator: nil)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Part 2 — publicly_reveal_attributes
  # ---------------------------------------------------------------------------

  describe '#publicly_reveal_attributes' do
    subject(:client) do
      described_class.new(wallet: wallet, broadcaster: broadcaster, certificate_verifier: verifier)
    end

    let(:verifier) { ->(cert) { cert } } # no-op verifier
    let(:certificate) do
      {
        type: BSV::Identity::Constants::KNOWN_IDENTITY_TYPES[:email_cert],
        serial_number: 'AAABBBCCC==',
        subject: IDENTITY_CLIENT_SPEC_PUBKEY,
        certifier: IDENTITY_CLIENT_SPEC_CERTIFIER,
        revocation_outpoint: 'abc123.0',
        fields: { 'email' => 'encrypted' },
        signature: 'deadbeef'
      }
    end
    let(:keyring) { { 'email' => [1, 2, 3, 4] } }
    let(:locking_hex) { "76a914#{'ff' * 20}88ac" }
    let(:mock_script) { instance_double(BSV::Script::Script, to_hex: locking_hex) }
    let(:mock_template) { instance_double(BSV::Script::PushDropTemplate, lock: mock_script) }
    let(:beef_bytes) { 'fake_beef_bytes' }
    let(:broadcaster) { instance_double(BSV::Overlay::TopicBroadcaster) }
    let(:broadcast_result) do
      BSV::Overlay::OverlayBroadcastResult.new(status: 'success', txid: 'ab' * 32, message: 'ok')
    end

    before do
      allow(BSV::Script::PushDropTemplate).to receive(:new).and_return(mock_template)
      allow(wallet).to receive_messages(
        prove_certificate: { keyring_for_verifier: keyring },
        create_action: { tx: beef_bytes, txid: 'ab' * 32 }
      )
      allow(BSV::Transaction::Transaction).to receive(:from_beef)
        .and_return(instance_double(BSV::Transaction::Transaction, txid_hex: 'ab' * 32))
      allow(broadcaster).to receive(:broadcast).and_return(broadcast_result)
    end

    it 'returns an OverlayBroadcastResult' do
      result = client.publicly_reveal_attributes(certificate, fields_to_reveal: ['email'])
      expect(result).to be_a(BSV::Overlay::OverlayBroadcastResult)
    end

    it 'calls prove_certificate with the anyone verifier key' do
      client.publicly_reveal_attributes(certificate, fields_to_reveal: ['email'])
      expect(wallet).to have_received(:prove_certificate).with(
        certificate: certificate, fields_to_reveal: ['email'],
        verifier: BSV::Script::PushDropTemplate::GENERATOR_PUBKEY_HEX,
        originator: nil
      )
    end

    it 'broadcasts to the tm_identity topic' do
      client.publicly_reveal_attributes(certificate, fields_to_reveal: ['email'])
      expect(broadcaster).to have_received(:broadcast)
    end

    context 'when certificate has no fields' do
      let(:certificate) { { fields: {}, type: 'x', serial_number: 'y', subject: IDENTITY_CLIENT_SPEC_PUBKEY } }

      it 'raises ArgumentError' do
        expect do
          client.publicly_reveal_attributes(certificate, fields_to_reveal: ['email'])
        end.to raise_error(ArgumentError, /no fields to reveal/)
      end
    end

    context 'when fields_to_reveal is empty' do
      it 'raises ArgumentError' do
        expect do
          client.publicly_reveal_attributes(certificate, fields_to_reveal: [])
        end.to raise_error(ArgumentError, /at least one field/)
      end
    end

    context 'when certificate verification fails' do
      let(:verifier) { ->(_cert) { raise 'Invalid signature' } }

      it 'raises with a descriptive message' do
        expect do
          client.publicly_reveal_attributes(certificate, fields_to_reveal: ['email'])
        end.to raise_error(RuntimeError, /verification failed/)
      end
    end

    context 'when using the default verifier' do
      subject(:client) do
        described_class.new(wallet: wallet, broadcaster: broadcaster)
      end

      it 'raises NotImplementedError' do
        expect do
          client.publicly_reveal_attributes(certificate, fields_to_reveal: ['email'])
        end.to raise_error(NotImplementedError, /BSV::Auth::Certificate/)
      end
    end

    context 'when create_action returns no tx' do
      before do
        allow(wallet).to receive(:create_action).and_return({ txid: nil, tx: nil })
      end

      it 'raises a RuntimeError' do
        expect do
          client.publicly_reveal_attributes(certificate, fields_to_reveal: ['email'])
        end.to raise_error(RuntimeError, /failed to create action/)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Part 2 — revoke_certificate_revelation
  # ---------------------------------------------------------------------------

  describe '#revoke_certificate_revelation' do
    subject(:client) do
      described_class.new(wallet: wallet, broadcaster: broadcaster, resolver: resolver,
                          certificate_verifier: ->(c) { c })
    end

    let(:serial_number) { 'AAABBBCCC==' }
    let(:resolver) { instance_double(BSV::Overlay::LookupResolver) }
    let(:broadcaster) { instance_double(BSV::Overlay::TopicBroadcaster) }

    # Minimal BEEF-like stub: just needs to respond to .transactions.last.transaction
    let(:mock_output) { instance_double(BSV::Transaction::TransactionOutput) }
    let(:inner_tx) { instance_double(BSV::Transaction::Transaction, txid_hex: 'deadbeef01', outputs: [mock_output]) }
    let(:beef_tx) { instance_double(BSV::Transaction::Beef::BeefTx, transaction: inner_tx) }
    let(:beef_obj) { instance_double(BSV::Transaction::Beef, transactions: [beef_tx]) }
    let(:beef_bytes) { 'fake_beef' }

    let(:output) { { 'beef' => beef_bytes, 'outputIndex' => 0 } }
    let(:answer) { BSV::Overlay::LookupAnswer.new(type: 'output-list', outputs: [output]) }

    let(:partial_tx) { instance_double(BSV::Transaction::Transaction) }
    let(:signed_tx) { instance_double(BSV::Transaction::Transaction) }
    let(:mock_script) { instance_double(BSV::Script::Script, to_hex: '00' * 107) }
    let(:mock_unlocker) { instance_double(BSV::Script::PushDropTemplate::Unlocker, sign: mock_script) }
    let(:mock_template) { instance_double(BSV::Script::PushDropTemplate, unlock: mock_unlocker) }
    let(:broadcast_result) do
      BSV::Overlay::OverlayBroadcastResult.new(status: 'success', txid: 'de' * 32, message: 'ok')
    end

    before do
      allow(resolver).to receive(:query).and_return(answer)
      allow(BSV::Transaction::Beef).to receive(:from_binary).and_return(beef_obj)
      allow(BSV::Script::PushDropTemplate).to receive(:new).and_return(mock_template)

      allow(wallet).to receive(:create_action) do |**kwargs|
        if kwargs[:inputs]
          { signable_transaction: { tx: beef_bytes, reference: 'REF123' } }
        else
          { tx: beef_bytes, txid: 'de' * 32 }
        end
      end

      allow(BSV::Transaction::Transaction).to receive(:from_beef).with(beef_bytes).and_return(partial_tx)
      allow(wallet).to receive(:sign_action).and_return({ tx: 'signed_beef', txid: 'de' * 32 })
      allow(BSV::Transaction::Transaction).to receive(:from_beef).with('signed_beef').and_return(signed_tx)
      allow(broadcaster).to receive(:broadcast).and_return(broadcast_result)
    end

    it 'queries the resolver for the serial number' do
      client.revoke_certificate_revelation(serial_number)
      expect(resolver).to have_received(:query) do |question|
        expect(question.service).to eq('ls_identity')
        expect(question.query[:serial_number]).to eq(serial_number)
      end
    end

    it 'broadcasts the spending transaction' do
      client.revoke_certificate_revelation(serial_number)
      expect(broadcaster).to have_received(:broadcast)
    end

    context 'when no outputs are found' do
      let(:answer) { BSV::Overlay::LookupAnswer.new(type: 'output-list', outputs: []) }

      it 'raises a RuntimeError' do
        expect do
          client.revoke_certificate_revelation(serial_number)
        end.to raise_error(RuntimeError, /no outputs found/)
      end
    end

    context 'when the lookup returns a non-output-list type' do
      let(:answer) { BSV::Overlay::LookupAnswer.new(type: 'freeform', outputs: []) }

      it 'raises a RuntimeError' do
        expect do
          client.revoke_certificate_revelation(serial_number)
        end.to raise_error(RuntimeError, /could not find revelation output/)
      end
    end
  end
end
