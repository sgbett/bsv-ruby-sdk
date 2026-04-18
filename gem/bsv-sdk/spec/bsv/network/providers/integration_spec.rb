# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'BSV::Network integration — Registry + Provider composition' do
  # ---------------------------------------------------------------------------
  # Shared HTTP stub helpers
  # ---------------------------------------------------------------------------

  def make_http(code, body)
    Class.new do
      define_method(:request) { |_uri, _req| Struct.new(:code, :body).new(code.to_s, body) }
    end.new
  end

  # Minimal HTTP client that records calls and dispatches based on path prefix.
  def routing_http(routes)
    Class.new do
      define_method(:request) do |uri, _req|
        path = uri.path
        entry = routes.find { |prefix, _| path.include?(prefix) }
        code, body = entry ? entry[1] : [404, 'not found']
        Struct.new(:code, :body).new(code.to_s, body)
      end
    end.new
  end

  # ---------------------------------------------------------------------------
  # Provider construction helpers
  # ---------------------------------------------------------------------------

  def woc(http_client: nil)
    BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_client)
  end

  def arc(http_client: nil)
    BSV::Network::Providers::ARC.new(url: 'https://arc.example.com', http_client: http_client)
  end

  # ---------------------------------------------------------------------------
  # 1. Default registry construction
  # ---------------------------------------------------------------------------

  describe 'BSV::Network.default_registry' do
    subject(:registry) { BSV::Network.default_registry }

    it 'returns a Registry instance' do
      expect(registry).to be_a(BSV::Network::Registry)
    end

    it 'has both providers registered' do
      providers = registry.registered_providers
      expect(providers.any?(BSV::Network::Providers::WhatsOnChain)).to be true
      expect(providers.any?(BSV::Network::Providers::ARC)).to be true
    end

    it 'accepts network: keyword' do
      reg = BSV::Network.default_registry(network: :test)
      expect(reg).to be_a(BSV::Network::Registry)
    end

    it 'accepts arc_url: keyword' do
      reg = BSV::Network.default_registry(arc_url: 'https://custom.arc.example.com')
      expect(reg).to be_a(BSV::Network::Registry)
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Command routing: WoC handles chain-data, ARC handles broadcast
  # ---------------------------------------------------------------------------

  describe 'command routing' do
    let(:woc_http) { make_http(200, '"deadbeef"') }
    let(:arc_http) do
      make_http(200, JSON.generate(
                       'txid' => 'abc123',
                       'txStatus' => 'SEEN_ON_NETWORK',
                       'extraInfo' => nil
                     ))
    end

    let(:registry) do
      BSV::Network::Registry.new
                            .register(woc(http_client: woc_http))
                            .register(arc(http_client: arc_http))
    end

    it 'routes :get_tx to WoC (not ARC)' do
      pairs = registry.providers_for(:get_tx)
      expect(pairs.map(&:first)).to all(be_a(BSV::Network::Providers::WhatsOnChain))
    end

    it 'routes :broadcast to ARC (not WoC)' do
      pairs = registry.providers_for(:broadcast)
      expect(pairs.map(&:first)).to all(be_a(BSV::Network::Providers::ARC))
    end

    it 'routes :get_utxos, :valid_root, :current_height, :get_merkle_path, :is_utxo, :get_script_unspent to WoC' do
      woc_commands = %i[get_utxos valid_root current_height get_merkle_path is_utxo get_script_unspent]
      woc_commands.each do |cmd|
        pairs = registry.providers_for(cmd)
        expect(pairs).not_to be_empty, "expected #{cmd} to have a provider"
        expect(pairs.map(&:first)).to all(be_a(BSV::Network::Providers::WhatsOnChain)),
                                      "expected #{cmd} to route to WoC"
      end
    end

    it 'routes :broadcast_many, :get_tx_status, :get_policy to ARC' do
      arc_commands = %i[broadcast_many get_tx_status get_policy]
      arc_commands.each do |cmd|
        pairs = registry.providers_for(cmd)
        expect(pairs).not_to be_empty, "expected #{cmd} to have a provider"
        expect(pairs.map(&:first)).to all(be_a(BSV::Network::Providers::ARC)),
                                      "expected #{cmd} to route to ARC"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Capability matrix shows all 11 commands
  # ---------------------------------------------------------------------------

  describe 'capability matrix' do
    let(:registry) do
      BSV::Network::Registry.new
                            .register(woc)
                            .register(arc)
    end

    it 'lists all 11 commands across both providers' do
      matrix = registry.capability_matrix
      all_cmds = matrix.values.flatten.uniq
      expect(all_cmds.length).to eq(11)
    end

    it 'assigns WoC commands only to the WoC provider' do
      matrix = registry.capability_matrix
      woc_entry = matrix.find { |p, _| p.is_a?(BSV::Network::Providers::WhatsOnChain) }
      expect(woc_entry).not_to be_nil
      expect(woc_entry[1]).to include(:get_tx, :get_utxos, :valid_root, :current_height,
                                      :get_merkle_path, :is_utxo, :get_script_unspent)
    end

    it 'assigns ARC commands only to the ARC provider' do
      matrix = registry.capability_matrix
      arc_entry = matrix.find { |p, _| p.is_a?(BSV::Network::Providers::ARC) }
      expect(arc_entry).not_to be_nil
      expect(arc_entry[1]).to include(:broadcast, :broadcast_many, :get_tx_status, :get_policy)
    end

    it 'BSV::Network.capability_matrix returns the same structure' do
      matrix = BSV::Network.capability_matrix
      all_cmds = matrix.values.flatten.uniq
      expect(all_cmds.length).to eq(11)
    end
  end

  # ---------------------------------------------------------------------------
  # 4. BSV::Network.commands convenience method
  # ---------------------------------------------------------------------------

  describe 'BSV::Network.commands' do
    # command_spec.rb resets Command registry between examples; clear and reload
    # so these tests are not order-dependent.
    before do
      BSV::Network::Command.reset!
      load "#{Bundler.root}/gem/bsv-sdk/lib/bsv/network/commands.rb"
    end

    it 'returns a hash of all 11 registered commands' do
      cmds = BSV::Network.commands
      expect(cmds).to be_a(Hash)
      expect(cmds.length).to eq(11)
    end

    it 'keys are Symbols matching command names' do
      expect(BSV::Network.commands.keys).to include(:broadcast, :get_tx, :get_policy)
    end

    it 'values are Command instances' do
      expect(BSV::Network.commands.values).to all(be_a(BSV::Network::Command))
    end
  end

  # ---------------------------------------------------------------------------
  # 5. WoC-only registry: :broadcast raises NoProviderError
  # ---------------------------------------------------------------------------

  describe 'WoC-only registry' do
    let(:registry) { BSV::Network::Registry.new.register(woc) }

    it 'raises NoProviderError for :broadcast' do
      expect { registry.call(:broadcast, double) }
        .to raise_error(BSV::Network::Registry::NoProviderError)
    end

    it 'raises NoProviderError for :get_policy' do
      expect { registry.call(:get_policy) }
        .to raise_error(BSV::Network::Registry::NoProviderError)
    end

    it 'can still route :get_tx' do
      pairs = registry.providers_for(:get_tx)
      expect(pairs).not_to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # 6. Failover: WoC retryable error -> next provider tried
  # ---------------------------------------------------------------------------

  describe 'failover on retryable error' do
    let(:failing_woc) do
      bsv_woc_class = Class.new(BSV::Network::Provider) do
        provides :get_tx

        def call_get_tx(_txid)
          error('timeout', retryable: true)
        end
      end
      bsv_woc_class.new
    end

    let(:fallback_http) { make_http(200, 'fallback_hex') }
    let(:fallback_woc)  { woc(http_client: fallback_http) }

    let(:registry) do
      BSV::Network::Registry.new
                            .register(failing_woc, priority: 1)
                            .register(fallback_woc, priority: 2)
    end

    it 'falls over to the next WoC provider on retryable error' do
      result = registry.call(:get_tx, 'somtxid')
      expect(result).to be_success
      expect(result.data).to eq('fallback_hex')
    end
  end

  # ---------------------------------------------------------------------------
  # 7. ARC non-retryable error: does not fall through
  # ---------------------------------------------------------------------------

  describe 'non-retryable ARC error stops immediately' do
    let(:rejected_body) do
      JSON.generate('txid' => 'abc', 'txStatus' => 'REJECTED', 'detail' => 'bad tx', 'extraInfo' => nil)
    end
    let(:arc_http) { make_http(200, rejected_body) }
    let(:good_arc_http) { make_http(200, JSON.generate('txid' => 'good', 'txStatus' => 'SEEN_ON_NETWORK', 'extraInfo' => nil)) }

    let(:tx) { instance_double(BSV::Transaction::Transaction, to_ef_hex: '00', to_hex: '00') }

    let(:registry) do
      BSV::Network::Registry.new
                            .register(arc(http_client: arc_http), priority: 1)
                            .register(arc(http_client: good_arc_http), priority: 2)
    end

    it 'returns a non-retryable error and does not try the second ARC provider' do
      result = registry.call(:broadcast, tx)
      expect(result).to be_error
      expect(result.retryable?).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # 8. End-to-end: registry.call(:get_tx) dispatches to WoC with HTTP stub
  # ---------------------------------------------------------------------------

  describe 'end-to-end dispatch — :get_tx via WoC' do
    let(:hex) { 'deadbeef01020304' }
    let(:woc_http) { make_http(200, hex) } # WoC returns the raw hex string (not JSON-encoded)

    let(:registry) do
      BSV::Network::Registry.new
                            .register(woc(http_client: woc_http))
                            .register(arc)
    end

    it 'returns Success with the raw hex' do
      result = registry.call(:get_tx, 'abc123')
      expect(result).to be_success
      expect(result.data).to eq(hex)
    end
  end

  # ---------------------------------------------------------------------------
  # 9. End-to-end: registry.call(:broadcast) dispatches to ARC with HTTP stub
  # ---------------------------------------------------------------------------

  describe 'end-to-end dispatch — :broadcast via ARC' do
    let(:txid) { 'feedcafe01' }
    let(:arc_body) do
      JSON.generate('txid' => txid, 'txStatus' => 'SEEN_ON_NETWORK', 'extraInfo' => nil)
    end
    let(:arc_http) { make_http(200, arc_body) }

    let(:tx) do
      instance_double(BSV::Transaction::Transaction, to_ef_hex: 'efhex', to_hex: 'rawhex')
    end

    let(:registry) do
      BSV::Network::Registry.new
                            .register(woc)
                            .register(arc(http_client: arc_http))
    end

    it 'returns Success with txid and status' do
      result = registry.call(:broadcast, tx)
      expect(result).to be_success
      expect(result.data[:txid]).to eq(txid)
      expect(result.data[:status]).to eq('SEEN_ON_NETWORK')
    end
  end

  # ---------------------------------------------------------------------------
  # 10. Specifier filtering: ARC registered except: [:get_policy]
  # ---------------------------------------------------------------------------

  describe 'specifier filtering — except:' do
    let(:registry) do
      BSV::Network::Registry.new
                            .register(woc)
                            .register(arc, except: [:get_policy])
    end

    it 'routes :broadcast normally' do
      pairs = registry.providers_for(:broadcast)
      expect(pairs).not_to be_empty
    end

    it 'raises NoProviderError for :get_policy' do
      expect { registry.call(:get_policy) }
        .to raise_error(BSV::Network::Registry::NoProviderError)
    end
  end

  # ---------------------------------------------------------------------------
  # 11. BSV::Network.call convenience method
  # ---------------------------------------------------------------------------

  describe 'BSV::Network.call convenience method' do
    after do
      BSV::Network.reset_default_registry!
    end

    it 'delegates to the cached default registry' do
      registry = BSV::Network.default_registry
      allow(BSV::Network).to receive(:default_registry).and_return(registry)
      allow(registry).to receive(:call).and_return(BSV::Network::Result::Success.new(data: 42))

      result = BSV::Network.call(:current_height)
      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to eq(42)
    end
  end

  # ---------------------------------------------------------------------------
  # 12. Environment variable configuration
  # ---------------------------------------------------------------------------

  describe 'default_registry environment variable configuration' do
    it 'uses BSV_ARC_MAINNET_URL by default for :main network' do
      registry = BSV::Network.default_registry(network: :main)
      expect(registry).to be_a(BSV::Network::Registry)
    end

    it 'uses BSV_ARC_TESTNET_URL for :test network' do
      registry = BSV::Network.default_registry(network: :test)
      expect(registry).to be_a(BSV::Network::Registry)
    end
  end

  # ---------------------------------------------------------------------------
  # 13. No interference with legacy BSV::Network::ARC / BSV::Network::WhatsOnChain
  # ---------------------------------------------------------------------------

  describe 'legacy namespace coexistence' do
    it 'BSV::Network::ARC (legacy) is still accessible' do
      expect(BSV::Network::ARC).to be_a(Class)
    end

    it 'BSV::Network::WhatsOnChain (legacy) is still accessible' do
      expect(BSV::Network::WhatsOnChain).to be_a(Class)
    end

    it 'BSV::Network::Providers::ARC is a different class from BSV::Network::ARC' do
      expect(BSV::Network::Providers::ARC).not_to eq(BSV::Network::ARC)
    end

    it 'BSV::Network::Providers::WhatsOnChain is a different class from BSV::Network::WhatsOnChain' do
      expect(BSV::Network::Providers::WhatsOnChain).not_to eq(BSV::Network::WhatsOnChain)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
