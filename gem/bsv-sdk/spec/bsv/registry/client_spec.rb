# frozen_string_literal: true

require 'spec_helper'

# Constants defined at spec-file scope to avoid Lint/ConstantDefinitionInBlock.
REGISTRY_SPEC_IDENTITY_KEY   = "02#{'ab' * 32}"
REGISTRY_SPEC_TXID           = 'cd' * 32
REGISTRY_SPEC_LOCKING_HEX    = "76a914#{'ff' * 20}88ac"
REGISTRY_SPEC_BEEF_BYTES     = 'fake_beef_bytes'

RSpec.describe 'BSV::Registry::Client' do
  subject(:client) do
    described_class.new(wallet: wallet, broadcaster: broadcaster, resolver: resolver)
  end

  let(:described_class) { BSV::Registry::Client }
  let(:broadcast_result) do
    BSV::Overlay::OverlayBroadcastResult.new(status: 'success', txid: REGISTRY_SPEC_TXID, message: 'ok')
  end
  let(:mock_script) { instance_double(BSV::Script::Script, to_hex: REGISTRY_SPEC_LOCKING_HEX) }
  let(:mock_template) { instance_double(BSV::Script::PushDropTemplate, lock: mock_script) }
  let(:basket_data) do
    BSV::Registry::BasketDefinitionData.new(
      basket_id: 'my-basket-001',
      name: 'My Basket',
      icon_url: 'https://example.com/icon.png',
      description: 'Stores my tokens',
      documentation_url: 'https://example.com/docs'
    )
  end
  let(:protocol_data) do
    BSV::Registry::ProtocolDefinitionData.new(
      protocol_id: [1, 'test-protocol'],
      name: 'Test Protocol',
      icon_url: 'https://example.com/proto.png',
      description: 'A test protocol',
      documentation_url: 'https://example.com/proto-docs'
    )
  end
  let(:cert_data) do
    BSV::Registry::CertificateDefinitionData.new(
      type: 'cert-type-base64==',
      name: 'Email Certificate',
      icon_url: 'https://example.com/cert.png',
      description: 'Certifies email ownership',
      documentation_url: 'https://example.com/cert-docs',
      fields: {}
    )
  end

  # Plain double — wallet is duck-typed, Interface is not loaded at boot.
  let(:wallet)      { double('wallet') } # rubocop:disable RSpec/VerifiedDoubles
  let(:broadcaster) { instance_double(BSV::Overlay::TopicBroadcaster) }
  let(:resolver)    { instance_double(BSV::Overlay::LookupResolver) }

  before do
    allow(wallet).to receive(:get_public_key)
      .with({ identity_key: true }, originator: nil)
      .and_return({ public_key: REGISTRY_SPEC_IDENTITY_KEY })
  end

  # ---------------------------------------------------------------------------
  # #register_definition
  # ---------------------------------------------------------------------------

  describe '#register_definition' do
    before do
      allow(BSV::Script::PushDropTemplate).to receive(:new).and_return(mock_template)
      allow(wallet).to receive(:create_action).and_return({ tx: REGISTRY_SPEC_BEEF_BYTES })
      allow(BSV::Transaction::Transaction).to receive(:from_beef)
        .and_return(instance_double(BSV::Transaction::Transaction, txid_hex: REGISTRY_SPEC_TXID))
      allow(broadcaster).to receive(:broadcast).and_return(broadcast_result)
    end

    context 'with a basket definition' do
      it 'returns an OverlayBroadcastResult' do
        result = client.register_definition(BSV::Registry::DefinitionType::BASKET, basket_data)
        expect(result).to be_a(BSV::Overlay::OverlayBroadcastResult)
      end

      it 'creates a PushDropTemplate with the wallet' do
        client.register_definition(BSV::Registry::DefinitionType::BASKET, basket_data)
        expect(BSV::Script::PushDropTemplate).to have_received(:new).with(wallet: wallet, originator: nil)
      end

      it 'locks with the basket protocol ID and anyone counterparty' do
        client.register_definition(BSV::Registry::DefinitionType::BASKET, basket_data)
        expect(mock_template).to have_received(:lock).with(
          fields: anything,
          protocol_id: BSV::Registry::Constants::PROTOCOL_BASKET,
          key_id: '1',
          counterparty: 'anyone'
        )
      end

      it 'calls create_action with the basket basket name' do
        client.register_definition(BSV::Registry::DefinitionType::BASKET, basket_data)
        expect(wallet).to have_received(:create_action) do |args, **_kw|
          expect(args[:outputs].first[:basket]).to eq('basketmap')
        end
      end

      it 'broadcasts to the basket topic' do
        client.register_definition(BSV::Registry::DefinitionType::BASKET, basket_data)
        expect(broadcaster).to have_received(:broadcast)
      end
    end

    context 'with a protocol definition' do
      it 'locks with the protocol protocol ID' do
        client.register_definition(BSV::Registry::DefinitionType::PROTOCOL, protocol_data)
        expect(mock_template).to have_received(:lock).with(
          fields: anything,
          protocol_id: BSV::Registry::Constants::PROTOCOL_PROTOCOL,
          key_id: '1',
          counterparty: 'anyone'
        )
      end

      it 'calls create_action with the protomap basket name' do
        client.register_definition(BSV::Registry::DefinitionType::PROTOCOL, protocol_data)
        expect(wallet).to have_received(:create_action) do |args, **_kw|
          expect(args[:outputs].first[:basket]).to eq('protomap')
        end
      end
    end

    context 'with a certificate definition' do
      it 'locks with the certmap protocol ID' do
        client.register_definition(BSV::Registry::DefinitionType::CERTIFICATE, cert_data)
        expect(mock_template).to have_received(:lock).with(
          fields: anything,
          protocol_id: BSV::Registry::Constants::PROTOCOL_CERTIFICATE,
          key_id: '1',
          counterparty: 'anyone'
        )
      end
    end

    context 'when create_action returns no tx' do
      before do
        allow(wallet).to receive(:create_action).and_return({ tx: nil })
      end

      it 'raises a RuntimeError' do
        expect do
          client.register_definition(BSV::Registry::DefinitionType::BASKET, basket_data)
        end.to raise_error(RuntimeError, /could not create.*registration transaction/)
      end
    end

    context 'with an originator' do
      subject(:client_with_originator) do
        described_class.new(wallet: wallet, broadcaster: broadcaster, originator: 'myapp.example.com')
      end

      before do
        allow(wallet).to receive(:get_public_key)
          .with({ identity_key: true }, originator: 'myapp.example.com')
          .and_return({ public_key: REGISTRY_SPEC_IDENTITY_KEY })
      end

      it 'passes the originator to create_action' do
        client_with_originator.register_definition(BSV::Registry::DefinitionType::BASKET, basket_data)
        expect(wallet).to have_received(:create_action) do |_args, originator:|
          expect(originator).to eq('myapp.example.com')
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Field ordering in buildPushDropFields
  # ---------------------------------------------------------------------------

  describe 'PushDrop field ordering' do
    before do
      allow(BSV::Script::PushDropTemplate).to receive(:new).and_return(mock_template)
      allow(wallet).to receive(:create_action).and_return({ tx: REGISTRY_SPEC_BEEF_BYTES })
      allow(BSV::Transaction::Transaction).to receive(:from_beef)
        .and_return(instance_double(BSV::Transaction::Transaction, txid_hex: REGISTRY_SPEC_TXID))
      allow(broadcaster).to receive(:broadcast).and_return(broadcast_result)
    end

    it 'encodes basket fields in correct order (basketID, name, iconURL, desc, docURL, operator)' do
      captured_fields = nil
      allow(mock_template).to receive(:lock) do |args|
        captured_fields = args[:fields]
        mock_script
      end

      client.register_definition(BSV::Registry::DefinitionType::BASKET, basket_data)

      expect(captured_fields[0]).to eq('my-basket-001'.b)
      expect(captured_fields[1]).to eq('My Basket'.b)
      expect(captured_fields[2]).to eq('https://example.com/icon.png'.b)
      expect(captured_fields[3]).to eq('Stores my tokens'.b)
      expect(captured_fields[4]).to eq('https://example.com/docs'.b)
      expect(captured_fields[5]).to eq(REGISTRY_SPEC_IDENTITY_KEY.b)
    end

    it 'encodes protocol fields with JSON-serialised protocolID first' do
      captured_fields = nil
      allow(mock_template).to receive(:lock) do |args|
        captured_fields = args[:fields]
        mock_script
      end

      client.register_definition(BSV::Registry::DefinitionType::PROTOCOL, protocol_data)

      expect(captured_fields[0]).to eq(JSON.generate([1, 'test-protocol']).b)
      expect(captured_fields[1]).to eq('Test Protocol'.b)
    end

    it 'encodes certificate fields with JSON-serialised fields map second-to-last' do
      cert_with_fields = BSV::Registry::CertificateDefinitionData.new(
        type: 'cert-base64==',
        name: 'My Cert',
        icon_url: '',
        description: '',
        documentation_url: '',
        fields: {
          'email' => BSV::Registry::CertificateFieldDescriptor.new(
            friendly_name: 'Email',
            description: 'Your email',
            type: 'text',
            field_icon: ''
          )
        }
      )

      captured_fields = nil
      allow(mock_template).to receive(:lock) do |args|
        captured_fields = args[:fields]
        mock_script
      end

      client.register_definition(BSV::Registry::DefinitionType::CERTIFICATE, cert_with_fields)

      parsed_fields = JSON.parse(captured_fields[5])
      expect(parsed_fields).to have_key('email')
      expect(parsed_fields['email']['friendlyName']).to eq('Email')
    end
  end

  # ---------------------------------------------------------------------------
  # #resolve
  # ---------------------------------------------------------------------------

  describe '#resolve' do
    let(:mock_output_tx) do
      tx_output = instance_double(
        BSV::Transaction::TransactionOutput,
        locking_script: mock_locking_script,
        satoshis: 1
      )
      instance_double(BSV::Transaction::Transaction,
                      txid_hex: REGISTRY_SPEC_TXID,
                      outputs: [tx_output])
    end

    # Build a locking script mock that returns the right field count for basket (7 = 5 + op + sig)
    let(:mock_locking_script) do
      fields = [
        'my-basket-001'.b,
        'My Basket'.b,
        'https://example.com/icon.png'.b,
        'Stores my tokens'.b,
        'https://example.com/docs'.b,
        REGISTRY_SPEC_IDENTITY_KEY.b,
        'fake_signature'.b # signature field — will be dropped
      ]
      script = instance_double(BSV::Script::Script)
      allow(script).to receive_messages(pushdrop_fields: fields, to_hex: REGISTRY_SPEC_LOCKING_HEX)
      script
    end

    let(:beef_obj) do
      beef_tx = instance_double(BSV::Transaction::Beef::BeefTx, transaction: mock_output_tx)
      instance_double(BSV::Transaction::Beef, transactions: [beef_tx])
    end

    let(:overlay_output) { { 'beef' => REGISTRY_SPEC_BEEF_BYTES, 'outputIndex' => 0 } }
    let(:answer) { BSV::Overlay::LookupAnswer.new(type: 'output-list', outputs: [overlay_output]) }

    before do
      allow(resolver).to receive(:query).and_return(answer)
      allow(BSV::Transaction::Beef).to receive(:from_binary).and_return(beef_obj)
    end

    it 'returns an array of RegisteredDefinition' do
      results = client.resolve(BSV::Registry::DefinitionType::BASKET, { basket_id: 'my-basket-001' })
      expect(results).to all(be_a(BSV::Registry::RegisteredDefinition))
    end

    it 'queries the resolver with the basket service name' do
      client.resolve(BSV::Registry::DefinitionType::BASKET, { basket_id: 'my-basket-001' })
      expect(resolver).to have_received(:query) do |question|
        expect(question.service).to eq('ls_basketmap')
      end
    end

    it 'parses the basket_id from the locking script' do
      results = client.resolve(BSV::Registry::DefinitionType::BASKET, { basket_id: 'my-basket-001' })
      expect(results.first.definition_data.basket_id).to eq('my-basket-001')
    end

    it 'parses the registry_operator from the locking script' do
      results = client.resolve(BSV::Registry::DefinitionType::BASKET, { basket_id: 'my-basket-001' })
      expect(results.first.definition_data.registry_operator).to eq(REGISTRY_SPEC_IDENTITY_KEY)
    end

    context 'when the lookup returns a non-output-list type' do
      let(:answer) { BSV::Overlay::LookupAnswer.new(type: 'freeform', outputs: []) }

      it 'returns an empty array' do
        expect(client.resolve(BSV::Registry::DefinitionType::BASKET, {})).to eq([])
      end
    end

    context 'with a protocol definition' do
      let(:mock_locking_script) do
        fields = [
          JSON.generate([1, 'test-protocol']).b,
          'Test Protocol'.b,
          'https://example.com/proto.png'.b,
          'A test protocol'.b,
          'https://example.com/proto-docs'.b,
          REGISTRY_SPEC_IDENTITY_KEY.b,
          'fake_signature'.b
        ]
        script = instance_double(BSV::Script::Script)
        allow(script).to receive_messages(pushdrop_fields: fields, to_hex: REGISTRY_SPEC_LOCKING_HEX)
        script
      end

      it 'parses the protocol_id from the locking script' do
        results = client.resolve(BSV::Registry::DefinitionType::PROTOCOL, { name: 'Test Protocol' })
        expect(results.first.definition_data.protocol_id).to eq([1, 'test-protocol'])
      end
    end

    context 'with a certificate definition' do
      let(:mock_locking_script) do
        fields_json = JSON.generate({
                                      'email' => {
                                        'friendlyName' => 'Email',
                                        'description' => 'Your email',
                                        'type' => 'text',
                                        'fieldIcon' => ''
                                      }
                                    })
        fields = [
          'cert-type-base64=='.b,
          'Email Certificate'.b,
          'https://example.com/cert.png'.b,
          'Certifies email ownership'.b,
          'https://example.com/cert-docs'.b,
          fields_json.b,
          REGISTRY_SPEC_IDENTITY_KEY.b,
          'fake_signature'.b
        ]
        script = instance_double(BSV::Script::Script)
        allow(script).to receive_messages(pushdrop_fields: fields, to_hex: REGISTRY_SPEC_LOCKING_HEX)
        script
      end

      it 'parses the certificate type from the locking script' do
        results = client.resolve(BSV::Registry::DefinitionType::CERTIFICATE, { type: 'cert-type-base64==' })
        expect(results.first.definition_data.type).to eq('cert-type-base64==')
      end

      it 'parses the certificate fields hash' do
        results = client.resolve(BSV::Registry::DefinitionType::CERTIFICATE, {})
        field_data = results.first.definition_data.fields['email']
        expect(field_data).to be_a(BSV::Registry::CertificateFieldDescriptor)
        expect(field_data.friendly_name).to eq('Email')
      end
    end

    context 'when an output fails to parse' do
      let(:bad_output) { { 'beef' => 'bad_beef', 'outputIndex' => 0 } }
      let(:answer) do
        BSV::Overlay::LookupAnswer.new(type: 'output-list', outputs: [bad_output, overlay_output])
      end

      before do
        allow(BSV::Transaction::Beef).to receive(:from_binary).with('bad_beef').and_raise(StandardError, 'bad BEEF')
        allow(BSV::Transaction::Beef).to receive(:from_binary).with(REGISTRY_SPEC_BEEF_BYTES).and_return(beef_obj)
      end

      it 'skips the invalid output and returns valid results' do
        results = client.resolve(BSV::Registry::DefinitionType::BASKET, {})
        expect(results.length).to eq(1)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #list_own_registry_entries
  # ---------------------------------------------------------------------------

  describe '#list_own_registry_entries' do
    let(:mock_locking_script) do
      fields = [
        'my-basket-001'.b,
        'My Basket'.b,
        'https://example.com/icon.png'.b,
        'Stores my tokens'.b,
        'https://example.com/docs'.b,
        REGISTRY_SPEC_IDENTITY_KEY.b,
        'fake_signature'.b
      ]
      script = instance_double(BSV::Script::Script)
      allow(script).to receive_messages(pushdrop_fields: fields, to_hex: REGISTRY_SPEC_LOCKING_HEX)
      script
    end

    let(:mock_tx_output) do
      instance_double(BSV::Transaction::TransactionOutput,
                      locking_script: mock_locking_script,
                      satoshis: 1)
    end

    let(:mock_tx) do
      instance_double(BSV::Transaction::Transaction,
                      txid_hex: REGISTRY_SPEC_TXID,
                      outputs: [mock_tx_output])
    end

    let(:mock_beef_tx) { instance_double(BSV::Transaction::Beef::BeefTx, transaction: mock_tx) }
    let(:mock_beef)    { instance_double(BSV::Transaction::Beef, transactions: [mock_beef_tx]) }

    let(:wallet_output) do
      { outpoint: "#{REGISTRY_SPEC_TXID}.0", satoshis: 1, spendable: true }
    end

    before do
      allow(wallet).to receive(:list_outputs)
        .with({ basket: 'basketmap', include: 'entire transactions' }, originator: nil)
        .and_return({ outputs: [wallet_output], beef: REGISTRY_SPEC_BEEF_BYTES })
      allow(BSV::Transaction::Beef).to receive(:from_binary).and_return(mock_beef)
    end

    it 'returns an array of RegisteredDefinition' do
      results = client.list_own_registry_entries(BSV::Registry::DefinitionType::BASKET)
      expect(results).to all(be_a(BSV::Registry::RegisteredDefinition))
    end

    it 'queries wallet for the correct basket' do
      client.list_own_registry_entries(BSV::Registry::DefinitionType::BASKET)
      expect(wallet).to have_received(:list_outputs) do |args, **_kw|
        expect(args[:basket]).to eq('basketmap')
      end
    end

    it 'parses the basket_id from the output' do
      results = client.list_own_registry_entries(BSV::Registry::DefinitionType::BASKET)
      expect(results.first.definition_data.basket_id).to eq('my-basket-001')
    end

    it 'sets the txid from the outpoint' do
      results = client.list_own_registry_entries(BSV::Registry::DefinitionType::BASKET)
      expect(results.first.txid).to eq(REGISTRY_SPEC_TXID)
    end

    it 'sets the output_index from the outpoint' do
      results = client.list_own_registry_entries(BSV::Registry::DefinitionType::BASKET)
      expect(results.first.output_index).to eq(0)
    end

    context 'when there are no outputs' do
      before do
        allow(wallet).to receive(:list_outputs)
          .and_return({ outputs: [], beef: REGISTRY_SPEC_BEEF_BYTES })
      end

      it 'returns an empty array' do
        expect(client.list_own_registry_entries(BSV::Registry::DefinitionType::BASKET)).to eq([])
      end
    end

    context 'when beef is nil' do
      before do
        allow(wallet).to receive(:list_outputs)
          .and_return({ outputs: [wallet_output], beef: nil })
      end

      it 'returns an empty array' do
        expect(client.list_own_registry_entries(BSV::Registry::DefinitionType::BASKET)).to eq([])
      end
    end

    context 'when output is not spendable' do
      let(:unspendable_output) do
        { outpoint: "#{REGISTRY_SPEC_TXID}.0", satoshis: 1, spendable: false }
      end

      before do
        allow(wallet).to receive(:list_outputs)
          .and_return({ outputs: [unspendable_output], beef: REGISTRY_SPEC_BEEF_BYTES })
      end

      it 'skips non-spendable outputs' do
        expect(client.list_own_registry_entries(BSV::Registry::DefinitionType::BASKET)).to eq([])
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #revoke_definition
  # ---------------------------------------------------------------------------

  describe '#revoke_definition' do
    let(:definition_data) do
      BSV::Registry::BasketDefinitionData.new(
        basket_id: 'my-basket-001',
        name: 'My Basket',
        icon_url: '',
        description: '',
        documentation_url: '',
        registry_operator: REGISTRY_SPEC_IDENTITY_KEY
      )
    end

    let(:registered) do
      BSV::Registry::RegisteredDefinition.new(
        definition_data: definition_data,
        txid: REGISTRY_SPEC_TXID,
        output_index: 0,
        locking_script: REGISTRY_SPEC_LOCKING_HEX,
        beef: REGISTRY_SPEC_BEEF_BYTES
      )
    end

    let(:partial_tx) { instance_double(BSV::Transaction::Transaction) }
    let(:signed_tx)  { instance_double(BSV::Transaction::Transaction) }
    let(:mock_unlock_script) { instance_double(BSV::Script::Script, to_hex: '00' * 107) }
    let(:mock_unlocker) { instance_double(BSV::Script::PushDropTemplate::Unlocker, sign: mock_unlock_script) }
    let(:mock_template_revoke) { instance_double(BSV::Script::PushDropTemplate, unlock: mock_unlocker) }

    before do
      allow(BSV::Script::PushDropTemplate).to receive(:new).and_return(mock_template_revoke)
      allow(BSV::Transaction::Transaction).to receive(:from_beef).with(REGISTRY_SPEC_BEEF_BYTES).and_return(partial_tx)
      allow(wallet).to receive_messages(create_action: { signable_transaction: { tx: REGISTRY_SPEC_BEEF_BYTES, reference: 'REF456' } }, sign_action: { tx: 'signed_beef' })
      allow(BSV::Transaction::Transaction).to receive(:from_beef).with('signed_beef').and_return(signed_tx)
      allow(broadcaster).to receive(:broadcast).and_return(broadcast_result)
    end

    it 'broadcasts the spending transaction' do
      client.revoke_definition(registered)
      expect(broadcaster).to have_received(:broadcast)
    end

    it 'creates a spending input for the correct outpoint' do
      client.revoke_definition(registered)
      expect(wallet).to have_received(:create_action) do |args, **_kw|
        expect(args[:inputs].first[:outpoint]).to eq("#{REGISTRY_SPEC_TXID}.0")
      end
    end

    it 'signs with the basket protocol ID' do
      client.revoke_definition(registered)
      expect(mock_template_revoke).to have_received(:unlock).with(
        protocol_id: BSV::Registry::Constants::PROTOCOL_BASKET,
        key_id: '1',
        counterparty: 'anyone'
      )
    end

    context 'when the definition does not belong to this wallet' do
      let(:definition_data) do
        BSV::Registry::BasketDefinitionData.new(
          basket_id: 'other-basket',
          name: 'Other',
          icon_url: '',
          description: '',
          documentation_url: '',
          registry_operator: "02#{'11' * 32}"
        )
      end

      it 'raises a RuntimeError about ownership' do
        expect do
          client.revoke_definition(registered)
        end.to raise_error(RuntimeError, /does not belong to the current wallet/)
      end
    end

    context 'when create_action returns no signable_transaction' do
      before do
        allow(wallet).to receive(:create_action).and_return({ signable_transaction: nil })
      end

      it 'raises a RuntimeError' do
        expect do
          client.revoke_definition(registered)
        end.to raise_error(RuntimeError, /could not create signable transaction/)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #update_definition
  # ---------------------------------------------------------------------------

  describe '#update_definition' do
    let(:definition_data) do
      BSV::Registry::BasketDefinitionData.new(
        basket_id: 'old-basket',
        name: 'Old Basket',
        icon_url: '',
        description: '',
        documentation_url: '',
        registry_operator: REGISTRY_SPEC_IDENTITY_KEY
      )
    end

    let(:registered) do
      BSV::Registry::RegisteredDefinition.new(
        definition_data: definition_data,
        txid: REGISTRY_SPEC_TXID,
        output_index: 0,
        locking_script: REGISTRY_SPEC_LOCKING_HEX,
        beef: REGISTRY_SPEC_BEEF_BYTES
      )
    end

    let(:new_data) do
      BSV::Registry::BasketDefinitionData.new(
        basket_id: 'new-basket',
        name: 'New Basket',
        icon_url: '',
        description: '',
        documentation_url: ''
      )
    end

    let(:partial_tx) { instance_double(BSV::Transaction::Transaction) }
    let(:signed_tx)  { instance_double(BSV::Transaction::Transaction) }
    let(:mock_unlock_script) { instance_double(BSV::Script::Script, to_hex: '00' * 107) }
    let(:mock_unlocker) { instance_double(BSV::Script::PushDropTemplate::Unlocker, sign: mock_unlock_script) }
    let(:mock_template_update) { instance_double(BSV::Script::PushDropTemplate, lock: mock_script, unlock: mock_unlocker) }

    before do
      allow(BSV::Script::PushDropTemplate).to receive(:new).and_return(mock_template_update)

      allow(wallet).to receive(:create_action) do |args, **_opts|
        if args.key?(:inputs)
          { signable_transaction: { tx: REGISTRY_SPEC_BEEF_BYTES, reference: 'REF789' } }
        else
          { tx: REGISTRY_SPEC_BEEF_BYTES }
        end
      end

      allow(BSV::Transaction::Transaction).to receive(:from_beef).with(REGISTRY_SPEC_BEEF_BYTES).and_return(partial_tx)
      allow(wallet).to receive(:sign_action).and_return({ tx: 'signed_beef' })
      allow(BSV::Transaction::Transaction).to receive(:from_beef).with('signed_beef').and_return(signed_tx)
      allow(broadcaster).to receive(:broadcast).and_return(broadcast_result)
    end

    it 'broadcasts the new registration after revoking' do
      client.update_definition(registered, new_data)
      # broadcast called twice — once for revoke, once for register
      expect(broadcaster).to have_received(:broadcast).twice
    end

    it 'raises ArgumentError when definition types do not match' do
      expect do
        client.update_definition(registered, cert_data)
      end.to raise_error(ArgumentError, /Cannot change definition type/)
    end
  end
end
