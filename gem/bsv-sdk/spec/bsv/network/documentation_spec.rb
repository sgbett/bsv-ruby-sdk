# frozen_string_literal: true

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'BSV::Network documentation generation' do
  before do
    BSV::Network::Command.reset!
    load 'bsv/network/commands.rb'
  end

  after do
    BSV::Network::Command.reset!
    load 'bsv/network/commands.rb'
  end

  describe '.command_docs' do
    subject(:docs) { BSV::Network.command_docs }

    it 'returns an Array of Hashes' do
      expect(docs).to be_an(Array)
      expect(docs).to all(be_a(Hash))
    end

    it 'includes all 11 standard commands' do
      expect(docs.size).to eq(11)
    end

    it 'returns commands sorted by name' do
      names = docs.map { |d| d[:name] }
      expect(names).to eq(names.sort)
    end

    it 'includes name, params, returns, and description for each command' do
      expect(docs).to all(include(:name, :params, :returns, :description))
    end

    it 'includes the :broadcast command with correct metadata' do
      broadcast = docs.find { |d| d[:name] == :broadcast }
      expect(broadcast).not_to be_nil
      expect(broadcast[:description]).to include('transaction')
    end
  end

  describe '.command_docs_markdown' do
    subject(:markdown) { BSV::Network.command_docs_markdown }

    it 'returns a Markdown table string' do
      expect(markdown).to include('| Command |')
      expect(markdown).to include('| :broadcast |')
    end

    it 'includes all 11 commands' do
      expect(markdown.scan(/^\| :/).size).to eq(11)
    end

    context 'when no commands are registered' do
      before { BSV::Network::Command.reset! }

      it 'returns a fallback message' do
        expect(BSV::Network.command_docs_markdown).to eq('No commands registered.')
      end
    end
  end

  describe '.capability_matrix_markdown' do
    subject(:markdown) { BSV::Network.capability_matrix_markdown(registry: registry) }

    let(:http) do
      Class.new do
        define_method(:request) { |_uri, _req| Struct.new(:code, :body).new('200', '{}') }
      end.new
    end

    let(:registry) do
      woc = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http)
      arc = BSV::Network::Providers::ARC.new(url: 'http://localhost', http_client: http)
      BSV::Network::Registry.new.register(woc).register(arc)
    end

    it 'returns a Markdown table' do
      expect(markdown).to include('| Command |')
      expect(markdown).to include('WhatsOnChain')
      expect(markdown).to include('ARC')
    end

    it 'shows check marks for supported commands' do
      expect(markdown).to include("\u2713")
    end

    context 'with an empty registry' do
      it 'returns a fallback message' do
        empty = BSV::Network::Registry.new
        expect(BSV::Network.capability_matrix_markdown(registry: empty)).to eq('No providers registered.')
      end
    end
  end

  describe 'Registry#commands_for' do
    let(:http) do
      Class.new do
        define_method(:request) { |_uri, _req| Struct.new(:code, :body).new('200', '{}') }
      end.new
    end

    let(:woc) { BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http) }
    let(:arc) { BSV::Network::Providers::ARC.new(url: 'http://localhost', http_client: http) }
    let(:registry) { BSV::Network::Registry.new.register(woc).register(arc) }

    it 'returns commands for WhatsOnChain' do
      commands = registry.commands_for(woc)
      expect(commands).to include(:get_tx, :get_utxos, :is_utxo, :get_merkle_path)
    end

    it 'returns commands for ARC' do
      commands = registry.commands_for(arc)
      expect(commands).to include(:broadcast, :get_tx_status)
    end

    it 'returns empty array for unregistered provider' do
      other = BSV::Network::Providers::ARC.new(url: 'http://other', http_client: http)
      expect(registry.commands_for(other)).to eq([])
    end
  end

  describe 'Registry#registered_providers' do
    let(:http) do
      Class.new do
        define_method(:request) { |_uri, _req| Struct.new(:code, :body).new('200', '{}') }
      end.new
    end

    let(:woc) { BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http) }
    let(:arc) { BSV::Network::Providers::ARC.new(url: 'http://localhost', http_client: http) }

    it 'returns all registered providers' do
      registry = BSV::Network::Registry.new.register(woc).register(arc)
      expect(registry.registered_providers).to contain_exactly(woc, arc)
    end

    it 'returns empty array for empty registry' do
      expect(BSV::Network::Registry.new.registered_providers).to eq([])
    end
  end
end
# rubocop:enable RSpec/DescribeClass
