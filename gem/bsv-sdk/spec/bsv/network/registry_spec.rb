# frozen_string_literal: true

RSpec.describe 'BSV::Network::Registry' do
  subject(:registry) { BSV::Network::Registry.new }

  # ---------------------------------------------------------------------------
  # Test provider subclasses
  # ---------------------------------------------------------------------------

  let(:provider_class) do
    Class.new(BSV::Network::Provider) do
      provides :get_tx, :broadcast

      def call_get_tx(txid)
        success(txid)
      end

      def call_broadcast(_tx)
        success('ok')
      end
    end
  end

  let(:failing_provider_class) do
    Class.new(BSV::Network::Provider) do
      provides :get_tx, :broadcast

      def call_get_tx(_txid)
        error('timeout', retryable: true)
      end

      def call_broadcast(_tx)
        error('timeout', retryable: true)
      end
    end
  end

  let(:fatal_provider_class) do
    Class.new(BSV::Network::Provider) do
      provides :get_tx, :broadcast

      def call_get_tx(_txid)
        error('auth failure', retryable: false)
      end

      def call_broadcast(_tx)
        error('auth failure', retryable: false)
      end
    end
  end

  let(:not_found_provider_class) do
    Class.new(BSV::Network::Provider) do
      provides :get_tx

      def call_get_tx(_txid)
        not_found
      end
    end
  end

  let(:broadcast_only_class) do
    Class.new(BSV::Network::Provider) do
      provides :broadcast

      def call_broadcast(_tx)
        success('broadcast ok')
      end
    end
  end

  let(:exploding_provider_class) do
    Class.new(BSV::Network::Provider) do
      provides :get_tx

      def call_get_tx(_txid)
        raise 'unexpected boom'
      end
    end
  end

  let(:provider)            { provider_class.new }
  let(:failing_provider)    { failing_provider_class.new }
  let(:fatal_provider)      { fatal_provider_class.new }
  let(:not_found_provider)  { not_found_provider_class.new }
  let(:broadcast_provider)  { broadcast_only_class.new }
  let(:exploding_provider)  { exploding_provider_class.new }

  # ---------------------------------------------------------------------------
  # #register
  # ---------------------------------------------------------------------------

  describe '#register' do
    it 'returns self for chaining' do
      expect(registry.register(provider)).to be(registry)
    end

    it 'adds the provider to registered_providers' do
      registry.register(provider)
      expect(registry.registered_providers).to include(provider)
    end

    it 'allows the same provider to be registered multiple times' do
      registry.register(provider, only: [:get_tx])
      registry.register(provider, only: [:broadcast])
      expect(registry.registered_providers.count(provider)).to eq(2)
    end
  end

  # ---------------------------------------------------------------------------
  # #call — basic dispatch
  # ---------------------------------------------------------------------------

  describe '#call' do
    context 'with one provider supporting the command' do
      before { registry.register(provider) }

      it 'returns Success from the provider' do
        result = registry.call(:get_tx, 'abc123')
        expect(result).to be_a(BSV::Network::Result::Success)
        expect(result.data).to eq('abc123')
      end
    end

    context 'when the provider does not support the command' do
      before { registry.register(broadcast_provider) }

      it 'raises NoProviderError' do
        expect { registry.call(:get_tx, 'abc') }
          .to raise_error(BSV::Network::Registry::NoProviderError)
      end
    end

    context 'with an empty registry' do
      it 'raises NoProviderError' do
        expect { registry.call(:get_tx, 'abc') }
          .to raise_error(BSV::Network::Registry::NoProviderError)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #call — failover semantics
  # ---------------------------------------------------------------------------

  describe '#call failover' do
    context 'first provider retryable error, second returns success' do
      before do
        registry.register(failing_provider, priority: 1)
        registry.register(provider, priority: 2)
      end

      it 'falls over to the second provider and returns Success' do
        result = registry.call(:get_tx, 'txid')
        expect(result).to be_a(BSV::Network::Result::Success)
        expect(result.data).to eq('txid')
      end
    end

    context 'first provider returns non-retryable error' do
      before do
        registry.register(fatal_provider, priority: 1)
        registry.register(provider, priority: 2)
      end

      it 'returns the error immediately without trying the second provider' do
        result = registry.call(:get_tx, 'txid')
        expect(result).to be_a(BSV::Network::Result::Error)
        expect(result.retryable?).to be false
        expect(result.message).to eq('auth failure')
      end
    end

    context 'first provider returns NotFound' do
      before do
        registry.register(not_found_provider, priority: 1)
        registry.register(provider, priority: 2)
      end

      it 'returns NotFound immediately without trying the second provider' do
        result = registry.call(:get_tx, 'txid')
        expect(result).to be_a(BSV::Network::Result::NotFound)
      end
    end

    context 'all providers fail with retryable errors' do
      let(:failing2) { failing_provider_class.new }

      before do
        registry.register(failing_provider, priority: 1)
        registry.register(failing2, priority: 2)
      end

      it 'returns the last retryable error' do
        result = registry.call(:get_tx, 'txid')
        expect(result).to be_a(BSV::Network::Result::Error)
        expect(result.retryable?).to be true
        expect(result.message).to eq('timeout')
      end
    end

    context 'single provider with retryable error and no fallback' do
      before { registry.register(failing_provider) }

      it 'returns the retryable error (no fallback available)' do
        result = registry.call(:get_tx, 'txid')
        expect(result).to be_a(BSV::Network::Result::Error)
        expect(result.retryable?).to be true
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #call — exception wrapping
  # ---------------------------------------------------------------------------

  describe '#call exception wrapping' do
    context 'when the provider raises a StandardError' do
      before do
        registry.register(exploding_provider, priority: 1)
        registry.register(provider, priority: 2)
      end

      it 'wraps the exception as a retryable error and falls over to the next provider' do
        result = registry.call(:get_tx, 'txid')
        expect(result).to be_a(BSV::Network::Result::Success)
      end
    end

    context 'when the only provider raises and no fallback' do
      before { registry.register(exploding_provider) }

      it 'returns a retryable Result::Error wrapping the exception message' do
        result = registry.call(:get_tx, 'txid')
        expect(result).to be_a(BSV::Network::Result::Error)
        expect(result.retryable?).to be true
        expect(result.message).to eq('unexpected boom')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Priority ordering
  # ---------------------------------------------------------------------------

  describe 'priority ordering' do
    let(:call_order) { [] }

    let(:recording_class) do
      log = call_order
      Class.new(BSV::Network::Provider) do
        provides :get_tx

        define_method(:call_get_tx) do |_txid|
          log << self
          error('retryable', retryable: true)
        end
      end
    end

    it 'tries lower priority number first' do
      p1 = recording_class.new
      p10 = recording_class.new

      registry.register(p10, priority: 10)
      registry.register(p1, priority: 1)

      registry.call(:get_tx, 'x')

      expect(call_order).to eq([p1, p10])
    end

    it 'uses registration order (FIFO) to break ties within same priority' do
      pa = recording_class.new
      pb = recording_class.new
      pc = recording_class.new

      registry.register(pa, priority: 5)
      registry.register(pb, priority: 5)
      registry.register(pc, priority: 5)

      registry.call(:get_tx, 'x')

      expect(call_order).to eq([pa, pb, pc])
    end
  end

  # ---------------------------------------------------------------------------
  # Specifier integration
  # ---------------------------------------------------------------------------

  describe 'specifier filtering' do
    context 'with only: [:broadcast]' do
      before { registry.register(provider, only: [:broadcast]) }

      it 'allows the provider for :broadcast' do
        result = registry.call(:broadcast, 'tx')
        expect(result).to be_a(BSV::Network::Result::Success)
      end

      it 'raises NoProviderError for :get_tx' do
        expect { registry.call(:get_tx, 'id') }
          .to raise_error(BSV::Network::Registry::NoProviderError)
      end
    end

    context 'with except: [:get_tx]' do
      before { registry.register(provider, except: [:get_tx]) }

      it 'allows the provider for :broadcast' do
        result = registry.call(:broadcast, 'tx')
        expect(result).to be_a(BSV::Network::Result::Success)
      end

      it 'raises NoProviderError for :get_tx' do
        expect { registry.call(:get_tx, 'id') }
          .to raise_error(BSV::Network::Registry::NoProviderError)
      end
    end

    context 'with filter:' do
      before do
        registry.register(provider, filter: ->(cmd) { cmd == :broadcast })
      end

      it 'allows commands passing the filter' do
        result = registry.call(:broadcast, 'tx')
        expect(result).to be_a(BSV::Network::Result::Success)
      end

      it 'raises NoProviderError for commands blocked by the filter' do
        expect { registry.call(:get_tx, 'id') }
          .to raise_error(BSV::Network::Registry::NoProviderError)
      end
    end

    context 'with only: []' do
      before { registry.register(provider, only: []) }

      it 'makes the provider invisible for all commands' do
        expect { registry.call(:get_tx, 'id') }
          .to raise_error(BSV::Network::Registry::NoProviderError)
        expect { registry.call(:broadcast, 'tx') }
          .to raise_error(BSV::Network::Registry::NoProviderError)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Same provider registered with different specifiers
  # ---------------------------------------------------------------------------

  describe 'same provider registered twice with different specifiers' do
    before do
      registry.register(provider, only: [:get_tx], priority: 1)
      registry.register(provider, only: [:broadcast], priority: 2)
    end

    it 'handles :get_tx via the first registration' do
      result = registry.call(:get_tx, 'id')
      expect(result).to be_a(BSV::Network::Result::Success)
    end

    it 'handles :broadcast via the second registration' do
      result = registry.call(:broadcast, 'tx')
      expect(result).to be_a(BSV::Network::Result::Success)
    end

    it 'reports two entries in registered_providers' do
      expect(registry.registered_providers.count(provider)).to eq(2)
    end
  end

  # ---------------------------------------------------------------------------
  # #providers_for
  # ---------------------------------------------------------------------------

  describe '#providers_for' do
    it 'returns an empty array when no providers match' do
      registry.register(broadcast_provider)
      expect(registry.providers_for(:get_tx)).to be_empty
    end

    it 'returns [provider, specifier] pairs in priority order' do
      p1 = provider_class.new
      p2 = provider_class.new

      registry.register(p2, priority: 10)
      registry.register(p1, priority: 1)

      pairs = registry.providers_for(:get_tx)
      expect(pairs.map(&:first)).to eq([p1, p2])
    end

    it 'includes the specifier as the second element of each pair' do
      registry.register(provider)
      pairs = registry.providers_for(:get_tx)
      expect(pairs.first.last).to be_a(BSV::Network::Specifier)
    end

    it 'excludes providers whose specifier does not allow the command' do
      registry.register(provider, only: [:broadcast])
      expect(registry.providers_for(:get_tx)).to be_empty
    end

    it 'returns both entries when the same provider is registered twice with different specifiers' do
      registry.register(provider, only: [:get_tx])
      registry.register(provider, only: [:get_tx])
      pairs = registry.providers_for(:get_tx)
      expect(pairs.size).to eq(2)
    end
  end

  # ---------------------------------------------------------------------------
  # #capability_matrix
  # ---------------------------------------------------------------------------

  describe '#capability_matrix' do
    it 'returns an empty hash for an empty registry' do
      expect(registry.capability_matrix).to eq({})
    end

    it 'maps providers to their specifier-filtered command names' do
      registry.register(provider)
      matrix = registry.capability_matrix
      expect(matrix[provider]).to match_array(%i[get_tx broadcast])
    end

    it 'respects specifier filtering in the matrix' do
      registry.register(provider, only: [:broadcast])
      matrix = registry.capability_matrix
      expect(matrix[provider]).to eq([:broadcast])
    end

    it 'excludes commands blocked by the specifier' do
      registry.register(provider, except: [:broadcast])
      matrix = registry.capability_matrix
      expect(matrix[provider]).not_to include(:broadcast)
      expect(matrix[provider]).to include(:get_tx)
    end

    it 'reflects only: [] as no capabilities' do
      registry.register(provider, only: [])
      matrix = registry.capability_matrix
      expect(matrix[provider]).to be_empty
    end

    it 'includes multiple providers as separate keys' do
      p1 = provider_class.new
      p2 = broadcast_only_class.new

      registry.register(p1)
      registry.register(p2)

      matrix = registry.capability_matrix
      expect(matrix.keys).to include(p1, p2)
      expect(matrix[p2]).to eq([:broadcast])
    end
  end
end
