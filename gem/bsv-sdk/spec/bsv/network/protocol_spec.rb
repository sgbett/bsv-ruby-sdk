# frozen_string_literal: true

RSpec.describe 'BSV::Network::Protocol' do
  let(:base_protocol) do
    Class.new(BSV::Network::Protocol) do
      endpoint :get_tx,    :get,  '/v1/tx/{txid}'
      endpoint :broadcast, :post, '/v1/tx', response: :json
    end
  end

  describe 'endpoint DSL' do
    it 'registers endpoints on the class' do
      eps = base_protocol.endpoints
      expect(eps[:get_tx]).to eq({ method: :get, path: '/v1/tx/{txid}', response: :raw })
      expect(eps[:broadcast]).to eq({ method: :post, path: '/v1/tx', response: :json })
    end

    it 'returns a frozen copy from .endpoints' do
      expect(base_protocol.endpoints).to be_frozen
    end
  end

  describe '.commands' do
    it 'returns a Set of declared command names' do
      expect(base_protocol.commands).to be_a(Set)
      expect(base_protocol.commands).to eq(Set[:get_tx, :broadcast])
    end

    it 'returns an empty Set when no endpoints are declared' do
      empty = Class.new(BSV::Network::Protocol)
      expect(empty.commands).to be_empty
    end
  end

  describe 'subclass isolation' do
    let(:child_protocol) do
      Class.new(base_protocol) do
        endpoint :health, :get, '/v1/health'
      end
    end

    it 'inherits parent endpoints' do
      expect(child_protocol.commands).to include(:get_tx, :broadcast)
    end

    it 'includes its own additional endpoints' do
      expect(child_protocol.commands).to include(:health)
    end

    it 'does not add child endpoints to the parent' do
      child_protocol # trigger class creation
      expect(base_protocol.commands).not_to include(:health)
    end

    it 'allows the child to override a parent endpoint' do
      override = Class.new(base_protocol) do
        endpoint :get_tx, :post, '/v2/tx/{txid}', response: :json
      end
      expect(override.endpoints[:get_tx]).to eq({ method: :post, path: '/v2/tx/{txid}', response: :json })
      expect(base_protocol.endpoints[:get_tx]).to eq({ method: :get, path: '/v1/tx/{txid}', response: :raw })
    end

    it 'sibling subclasses do not share endpoints' do
      sibling_a = Class.new(base_protocol) do
        endpoint :only_in_a, :get, '/only-a'
      end
      sibling_b = Class.new(base_protocol) do
        endpoint :only_in_b, :get, '/only-b'
      end
      expect(sibling_a.commands).not_to include(:only_in_b)
      expect(sibling_b.commands).not_to include(:only_in_a)
    end
  end

  describe 'subscription DSL' do
    let(:sub_protocol) do
      Class.new(BSV::Network::Protocol) do
        subscription :on_tx, '/ws/tx', event: 'tx'
      end
    end

    it 'stores the subscription definition without error' do
      expect(sub_protocol.subscriptions[:on_tx]).to eq({ path: '/ws/tx', event: 'tx' })
    end

    it 'returns a frozen copy from .subscriptions' do
      expect(sub_protocol.subscriptions).to be_frozen
    end

    it 'subscription does not appear in commands' do
      expect(sub_protocol.commands).not_to include(:on_tx)
    end
  end

  describe '#initialize' do
    let(:klass) { Class.new(BSV::Network::Protocol) }

    it 'stores base_url, api_key, network, and http_client' do
      client = Object.new
      p = klass.new(base_url: 'https://example.com', api_key: 'key123', network: 'main', http_client: client)
      expect(p.base_url).to eq('https://example.com')
      expect(p.api_key).to eq('key123')
      expect(p.network).to eq('main')
      expect(p.http_client).to be(client)
    end

    it 'interpolates {network} in base_url' do
      p = klass.new(base_url: 'https://api.example.com/v1/bsv/{network}', network: 'main')
      expect(p.base_url).to eq('https://api.example.com/v1/bsv/main')
    end

    it 'accepts a Symbol for network and converts it to string in the URL' do
      p = klass.new(base_url: 'https://api.example.com/{network}', network: :test)
      expect(p.base_url).to eq('https://api.example.com/test')
    end

    it 'strips trailing slash from base_url' do
      p = klass.new(base_url: 'https://example.com/')
      expect(p.base_url).to eq('https://example.com')
    end

    it 'strips trailing slash after network interpolation' do
      p = klass.new(base_url: 'https://example.com/{network}/', network: 'main')
      expect(p.base_url).to eq('https://example.com/main')
    end

    it 'raises ArgumentError when {network} is present but network: is not provided' do
      expect do
        klass.new(base_url: 'https://api.example.com/v1/bsv/{network}')
      end.to raise_error(ArgumentError, /network/)
    end

    it 'allows nil api_key and http_client' do
      p = klass.new(base_url: 'https://example.com')
      expect(p.api_key).to be_nil
      expect(p.http_client).to be_nil
    end
  end

  describe '#call' do
    let(:instance) { Class.new(BSV::Network::Protocol).new(base_url: 'https://example.com') }

    it 'raises NotImplementedError (HTTP dispatch is Task 3)' do
      expect { instance.call(:get_tx, 'abc123') }.to raise_error(NotImplementedError)
    end
  end
end
