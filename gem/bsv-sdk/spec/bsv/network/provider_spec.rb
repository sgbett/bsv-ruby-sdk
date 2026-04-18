# frozen_string_literal: true

# Test subclasses — defined outside the RSpec.describe block to avoid
# Lint/ConstantDefinitionInBlock and RSpec/LeakyConstantDeclaration offences.

class ProviderTestBase < BSV::Network::Provider
  provides :get_tx, :broadcast

  def call_get_tx(txid)
    success(txid)
  end

  def call_broadcast(_tx)
    error('rejected', retryable: false)
  end
end

class ProviderTestChild < ProviderTestBase
  provides :query_status

  def call_query_status(txid)
    success("status:#{txid}")
  end
end

class ProviderTestEmpty < BSV::Network::Provider; end

class ProviderTestIncomplete < BSV::Network::Provider
  provides :get_tx
  # call_get_tx intentionally omitted
end

RSpec.describe 'BSV::Network::Provider' do
  describe '.capabilities' do
    it 'returns the declared command names as Symbols' do
      expect(ProviderTestBase.capabilities).to include(:get_tx, :broadcast)
    end

    it 'returns a frozen set' do
      expect(ProviderTestBase.capabilities).to be_frozen
    end

    it 'is empty when no commands have been declared' do
      expect(ProviderTestEmpty.capabilities).to be_empty
    end

    it 'inherits parent capabilities in a child class' do
      expect(ProviderTestChild.capabilities).to include(:get_tx, :broadcast, :query_status)
    end

    it 'does not pollute the parent capabilities with child additions' do
      expect(ProviderTestBase.capabilities).not_to include(:query_status)
    end
  end

  describe '.provides' do
    it 'coerces String arguments to Symbols' do
      klass = Class.new(BSV::Network::Provider) { provides 'some_command' }
      expect(klass.capabilities).to include(:some_command)
    end

    it 'is idempotent when the same name is declared multiple times' do
      klass = Class.new(BSV::Network::Provider) do
        provides :duplicate
        provides :duplicate
      end
      expect(klass.capabilities.count { |c| c == :duplicate }).to eq(1)
    end

    it 'accumulates across multiple provides calls' do
      klass = Class.new(BSV::Network::Provider) do
        provides :alpha
        provides :beta
      end
      expect(klass.capabilities).to include(:alpha, :beta)
    end
  end

  describe '#call' do
    let(:provider) { ProviderTestBase.new }

    it 'dispatches :get_tx to call_get_tx and returns a Result::Success' do
      result = provider.call(:get_tx, 'abc123')
      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to eq('abc123')
    end

    it 'dispatches :broadcast to call_broadcast and returns a Result::Error' do
      result = provider.call(:broadcast, nil)
      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.message).to eq('rejected')
      expect(result.retryable?).to be false
    end

    it 'accepts a String command name (coerced to Symbol)' do
      result = provider.call('get_tx', 'xyz')
      expect(result.success?).to be true
    end

    it 'raises ArgumentError for an unsupported command' do
      expect { provider.call(:unsupported) }.to raise_error(
        ArgumentError, /does not provide command :unsupported/
      )
    end

    it 'raises ArgumentError mentioning which commands are available' do
      expect { provider.call(:nonexistent) }.to raise_error(
        ArgumentError, /Provided:/
      )
    end

    it 'raises NoMethodError naturally when call_<name> is not implemented' do
      incomplete = ProviderTestIncomplete.new
      expect { incomplete.call(:get_tx) }.to raise_error(NoMethodError)
    end

    context 'with a child provider' do
      let(:child) { ProviderTestChild.new }

      it 'dispatches inherited commands' do
        result = child.call(:get_tx, 'parent_cmd')
        expect(result.success?).to be true
        expect(result.data).to eq('parent_cmd')
      end

      it 'dispatches child-specific commands' do
        result = child.call(:query_status, 'tx42')
        expect(result.success?).to be true
        expect(result.data).to eq('status:tx42')
      end
    end
  end

  describe 'result helper methods' do
    it 'success() returns a Result::Success with the given data' do
      klass = Class.new(BSV::Network::Provider) do
        provides :fetch
        def call_fetch(val)
          success(val)
        end
      end
      result = klass.new.call(:fetch, 'payload')
      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to eq('payload')
    end

    it 'error() returns a Result::Error with retryable: true' do
      klass = Class.new(BSV::Network::Provider) do
        provides :failing
        def call_failing
          error('oops', retryable: true)
        end
      end
      result = klass.new.call(:failing)
      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.message).to eq('oops')
      expect(result.retryable?).to be true
    end

    it 'error() defaults retryable to false' do
      klass = Class.new(BSV::Network::Provider) do
        provides :failing
        def call_failing
          error('oops')
        end
      end
      result = klass.new.call(:failing)
      expect(result.retryable?).to be false
    end

    it 'not_found() returns a Result::NotFound' do
      klass = Class.new(BSV::Network::Provider) do
        provides :missing
        def call_missing
          not_found
        end
      end
      result = klass.new.call(:missing)
      expect(result).to be_a(BSV::Network::Result::NotFound)
      expect(result.not_found?).to be true
    end
  end

  describe 'constructor' do
    it 'stores an injectable http_client accessible to subclass' do
      klass = Class.new(BSV::Network::Provider) do
        provides :ping
        def call_ping
          success(@http_client)
        end
      end
      sentinel = Object.new
      result = klass.new(http_client: sentinel).call(:ping)
      expect(result.data).to equal(sentinel)
    end

    it 'defaults http_client to nil when not supplied' do
      klass = Class.new(BSV::Network::Provider) do
        provides :ping
        def call_ping
          success(@http_client)
        end
      end
      expect(klass.new.call(:ping).data).to be_nil
    end

    it 'stores arbitrary options for subclass use' do
      klass = Class.new(BSV::Network::Provider) do
        provides :ping
        def call_ping
          success(@options)
        end
      end
      result = klass.new(url: 'https://example.com', api_key: 'secret').call(:ping)
      expect(result.data).to eq(url: 'https://example.com', api_key: 'secret')
    end

    it 'stores an empty options hash when no options supplied' do
      klass = Class.new(BSV::Network::Provider) do
        provides :ping
        def call_ping
          success(@options)
        end
      end
      expect(klass.new.call(:ping).data).to eq({})
    end
  end
end
