# frozen_string_literal: true

RSpec.describe 'BSV::Registry types' do
  describe 'BSV::Registry::DefinitionType' do
    it 'defines BASKET constant' do
      expect(BSV::Registry::DefinitionType::BASKET).to eq('basket')
    end

    it 'defines PROTOCOL constant' do
      expect(BSV::Registry::DefinitionType::PROTOCOL).to eq('protocol')
    end

    it 'defines CERTIFICATE constant' do
      expect(BSV::Registry::DefinitionType::CERTIFICATE).to eq('certificate')
    end

    it 'exposes ALL containing all three types' do
      expect(BSV::Registry::DefinitionType::ALL).to contain_exactly('basket', 'protocol', 'certificate')
    end
  end

  describe 'BSV::Registry::CertificateFieldDescriptor' do
    let(:descriptor) do
      BSV::Registry::CertificateFieldDescriptor.new(
        friendly_name: 'Email Address',
        description: 'The user\'s email',
        type: 'text',
        field_icon: 'https://example.com/email.png'
      )
    end

    it 'stores friendly_name' do
      expect(descriptor.friendly_name).to eq('Email Address')
    end

    it 'stores description' do
      expect(descriptor.description).to eq('The user\'s email')
    end

    it 'stores type' do
      expect(descriptor.type).to eq('text')
    end

    it 'stores field_icon' do
      expect(descriptor.field_icon).to eq('https://example.com/email.png')
    end

    it 'serialises to a Hash with camelCase keys' do
      h = descriptor.to_h
      expect(h['friendlyName']).to eq('Email Address')
      expect(h['description']).to eq('The user\'s email')
      expect(h['type']).to eq('text')
      expect(h['fieldIcon']).to eq('https://example.com/email.png')
    end
  end

  describe 'BSV::Registry::BasketDefinitionData' do
    let(:data) do
      BSV::Registry::BasketDefinitionData.new(
        basket_id: 'my-basket-001',
        name: 'My Basket',
        icon_url: 'https://example.com/icon.png',
        description: 'Stores my tokens',
        documentation_url: 'https://example.com/docs'
      )
    end

    it 'reports definition_type as basket' do
      expect(data.definition_type).to eq(BSV::Registry::DefinitionType::BASKET)
    end

    it 'stores basket_id' do
      expect(data.basket_id).to eq('my-basket-001')
    end

    it 'stores name' do
      expect(data.name).to eq('My Basket')
    end

    it 'stores icon_url' do
      expect(data.icon_url).to eq('https://example.com/icon.png')
    end

    it 'stores description' do
      expect(data.description).to eq('Stores my tokens')
    end

    it 'stores documentation_url' do
      expect(data.documentation_url).to eq('https://example.com/docs')
    end

    it 'defaults registry_operator to nil' do
      expect(data.registry_operator).to be_nil
    end

    it 'accepts an explicit registry_operator' do
      data_with_op = BSV::Registry::BasketDefinitionData.new(
        basket_id: 'x',
        name: 'X',
        icon_url: '',
        description: '',
        documentation_url: '',
        registry_operator: '02abcd'
      )
      expect(data_with_op.registry_operator).to eq('02abcd')
    end
  end

  describe 'BSV::Registry::ProtocolDefinitionData' do
    let(:data) do
      BSV::Registry::ProtocolDefinitionData.new(
        protocol_id: [1, 'my-protocol'],
        name: 'My Protocol',
        icon_url: 'https://example.com/proto.png',
        description: 'A test protocol',
        documentation_url: 'https://example.com/proto-docs'
      )
    end

    it 'reports definition_type as protocol' do
      expect(data.definition_type).to eq(BSV::Registry::DefinitionType::PROTOCOL)
    end

    it 'stores protocol_id' do
      expect(data.protocol_id).to eq([1, 'my-protocol'])
    end

    it 'stores name, icon_url, description, documentation_url' do
      expect(data.name).to eq('My Protocol')
      expect(data.icon_url).to eq('https://example.com/proto.png')
      expect(data.description).to eq('A test protocol')
      expect(data.documentation_url).to eq('https://example.com/proto-docs')
    end

    it 'defaults registry_operator to nil' do
      expect(data.registry_operator).to be_nil
    end
  end

  describe 'BSV::Registry::CertificateDefinitionData' do
    let(:fields) do
      {
        'email' => BSV::Registry::CertificateFieldDescriptor.new(
          friendly_name: 'Email',
          description: 'Email address',
          type: 'text',
          field_icon: ''
        )
      }
    end

    let(:data) do
      BSV::Registry::CertificateDefinitionData.new(
        type: 'cert-type-base64==',
        name: 'Email Certificate',
        icon_url: 'https://example.com/cert.png',
        description: 'Certifies email ownership',
        documentation_url: 'https://example.com/cert-docs',
        fields: fields
      )
    end

    it 'reports definition_type as certificate' do
      expect(data.definition_type).to eq(BSV::Registry::DefinitionType::CERTIFICATE)
    end

    it 'stores type' do
      expect(data.type).to eq('cert-type-base64==')
    end

    it 'stores fields' do
      expect(data.fields).to have_key('email')
    end

    it 'defaults fields to an empty hash' do
      d = BSV::Registry::CertificateDefinitionData.new(
        type: 't', name: 'n', icon_url: '', description: '', documentation_url: ''
      )
      expect(d.fields).to eq({})
    end
  end

  describe 'BSV::Registry::RegisteredDefinition' do
    let(:definition_data) do
      BSV::Registry::BasketDefinitionData.new(
        basket_id: 'test-basket',
        name: 'Test',
        icon_url: '',
        description: '',
        documentation_url: ''
      )
    end

    let(:registered) do
      BSV::Registry::RegisteredDefinition.new(
        definition_data: definition_data,
        txid: 'ab' * 32,
        output_index: 0,
        locking_script: 'deadbeef',
        beef: 'rawbeef'
      )
    end

    it 'exposes definition_type from the embedded data' do
      expect(registered.definition_type).to eq(BSV::Registry::DefinitionType::BASKET)
    end

    it 'stores txid' do
      expect(registered.txid).to eq('ab' * 32)
    end

    it 'stores output_index' do
      expect(registered.output_index).to eq(0)
    end

    it 'stores locking_script' do
      expect(registered.locking_script).to eq('deadbeef')
    end

    it 'stores beef' do
      expect(registered.beef).to eq('rawbeef')
    end

    it 'defaults satoshis to 1' do
      expect(registered.satoshis).to eq(1)
    end

    it 'stores explicit satoshis' do
      r = BSV::Registry::RegisteredDefinition.new(
        definition_data: definition_data,
        txid: 'ab' * 32,
        output_index: 0,
        locking_script: '',
        beef: '',
        satoshis: 42
      )
      expect(r.satoshis).to eq(42)
    end
  end
end
