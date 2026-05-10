# frozen_string_literal: true

RSpec.describe 'BSV::Network::Provider' do
  subject(:provider) { BSV::Network::Provider }

  let(:http_client) { double('http_client') } # rubocop:disable RSpec/VerifiedDoubles

  let(:arc_class)        { BSV::Network::Protocols::ARC }
  let(:woc_class)        { BSV::Network::Protocols::WoCREST }
  let(:chaintracks_class) { BSV::Network::Protocols::Chaintracks }
  let(:ordinals_class) { BSV::Network::Protocols::Ordinals }

  # ── Constructor ──────────────────────────────────────────────────────────────

  describe '.new' do
    it 'stores the provider name' do
      p = provider.new('GorillaPool')
      expect(p.name).to eq('GorillaPool')
    end

    it 'creates a provider with no protocols when no block is given' do
      p = provider.new('Empty')
      expect(p.protocols).to be_empty
    end

    it 'creates a provider with empty commands when no block is given' do
      p = provider.new('Empty')
      expect(p.commands).to be_empty
    end

    it 'yields self to the block for DSL calls' do
      yielded = nil
      p = provider.new('Test') { |pr| yielded = pr }
      expect(yielded).to be(p)
    end

    it 'defaults auth to :none' do
      p = provider.new('X')
      expect(p.auth).to eq(:none)
    end

    it 'defaults rate_limit to nil' do
      p = provider.new('X')
      expect(p.rate_limit).to be_nil
    end
  end

  # ── #auth / #rate_limit / #authenticated? ─────────────────────────────────────

  describe '#auth' do
    it 'stores an api_key auth hash' do
      p = provider.new('X', auth: { api_key: 'k' })
      expect(p.auth).to eq({ api_key: 'k' })
    end

    it 'stores a bearer auth hash' do
      p = provider.new('X', auth: { bearer: 'token' })
      expect(p.auth).to eq({ bearer: 'token' })
    end

    it 'normalises nil to :none' do
      p = provider.new('X', auth: nil)
      expect(p.auth).to eq(:none)
    end

    it 'normalises empty hash to :none' do
      p = provider.new('X', auth: {})
      expect(p.auth).to eq(:none)
    end
  end

  describe '#rate_limit' do
    it 'stores the supplied rate limit' do
      p = provider.new('X', rate_limit: 10)
      expect(p.rate_limit).to eq(10)
    end

    it 'accepts rate_limit: 0 as a valid value' do
      p = provider.new('X', rate_limit: 0)
      expect(p.rate_limit).to eq(0)
    end

    it 'defaults to nil when not supplied' do
      p = provider.new('X')
      expect(p.rate_limit).to be_nil
    end
  end

  describe '#authenticated?' do
    it 'returns false when auth is :none (default)' do
      p = provider.new('X')
      expect(p.authenticated?).to be(false)
    end

    it 'returns true when auth is an api_key hash' do
      p = provider.new('X', auth: { api_key: 'x' })
      expect(p.authenticated?).to be(true)
    end

    it 'returns true when auth is a bearer hash' do
      p = provider.new('X', auth: { bearer: 'token' })
      expect(p.authenticated?).to be(true)
    end

    it 'returns false when auth is an empty hash' do
      p = provider.new('X', auth: {})
      expect(p.authenticated?).to be(false)
    end

    it 'returns false when auth is nil' do
      p = provider.new('X', auth: nil)
      expect(p.authenticated?).to be(false)
    end
  end

  # ── Block DSL ─────────────────────────────────────────────────────────────────

  describe '#protocol' do
    it 'registers a protocol instance in the block' do
      p = provider.new('GorillaPool') do |pr|
        pr.protocol arc_class, base_url: 'https://arcade.gorillapool.io', http_client: http_client
      end
      expect(p.protocols.length).to eq(1)
      expect(p.protocols.first).to be_a(arc_class)
    end

    it 'returns the created protocol instance' do
      instance = nil
      provider.new('Test') do |pr|
        instance = pr.protocol arc_class, base_url: 'https://example.com', http_client: http_client
      end
      expect(instance).to be_a(arc_class)
    end

    it 'registers multiple protocols' do
      p = provider.new('Multi') do |pr|
        pr.protocol arc_class, base_url: 'https://arc.example.com', http_client: http_client
        pr.protocol chaintracks_class,  base_url: 'https://ct.example.com',     http_client: http_client
        pr.protocol ordinals_class,     base_url: 'https://ord.example.com',    http_client: http_client
      end
      expect(p.protocols.length).to eq(3)
    end

    it 'is callable after block execution (provider remains mutable)' do
      p = provider.new('Growing')
      expect(p.protocols).to be_empty

      p.protocol arc_class, base_url: 'https://arc.example.com', http_client: http_client
      expect(p.protocols.length).to eq(1)
    end

    it 'accepts extra kwargs like deployment_id for ARC' do
      p = provider.new('ARC') do |pr|
        pr.protocol arc_class,
                    base_url: 'https://arc.example.com',
                    deployment_id: 'my-deployment',
                    http_client: http_client
      end
      expect(p.protocols.first).to be_a(arc_class)
    end
  end

  # ── #protocols reader ─────────────────────────────────────────────────────────

  describe '#protocols' do
    it 'returns a frozen copy (not the internal array)' do
      p = provider.new('Test') do |pr|
        pr.protocol chaintracks_class, base_url: 'https://ct.example.com', http_client: http_client
      end
      copy = p.protocols
      expect(copy).to be_frozen
      expect { copy << 'anything' }.to raise_error(FrozenError)
    end

    it 'preserves registration order' do
      p = provider.new('Ordered') do |pr|
        pr.protocol chaintracks_class, base_url: 'https://ct.example.com',  http_client: http_client
        pr.protocol ordinals_class,    base_url: 'https://ord.example.com', http_client: http_client
      end
      expect(p.protocols.map(&:class)).to eq([chaintracks_class, ordinals_class])
    end
  end

  # ── #commands ────────────────────────────────────────────────────────────────

  describe '#commands' do
    it 'returns a Set' do
      p = provider.new('Test')
      expect(p.commands).to be_a(Set)
    end

    it 'returns empty Set when no protocols are registered' do
      p = provider.new('Empty')
      expect(p.commands).to be_empty
    end

    it 'returns the union of all protocol commands' do
      p = provider.new('Union') do |pr|
        pr.protocol chaintracks_class, base_url: 'https://ct.example.com',  http_client: http_client
        pr.protocol ordinals_class,    base_url: 'https://ord.example.com', http_client: http_client
      end
      expected = chaintracks_class.commands | ordinals_class.commands
      expect(p.commands).to eq(expected)
    end

    it 'includes commands from all protocols (ARC + WoCREST)' do
      p = provider.new('Full') do |pr|
        pr.protocol arc_class, base_url: 'https://arc.example.com', http_client: http_client
        pr.protocol woc_class, base_url: 'https://api.whatsonchain.com/v1/bsv/main', http_client: http_client
      end
      expect(p.commands).to include(:broadcast, :get_tx, :current_height, :health)
    end
  end

  # ── #call dispatch ────────────────────────────────────────────────────────────

  describe '#call' do
    let(:mock_response) do
      fake_http_response(200, '{"txid":"abc123","txStatus":"MINED"}')
    end

    it 'dispatches to the correct protocol' do
      allow(http_client).to receive(:request).and_return(mock_response)

      p = provider.new('Dispatch') do |pr|
        pr.protocol arc_class, base_url: 'https://arc.example.com', http_client: http_client
      end

      # ARC broadcast uses the escape hatch call_broadcast — pass a minimal tx double
      tx = double('tx') # rubocop:disable RSpec/VerifiedDoubles
      allow(tx).to receive(:to_ef_hex).and_return('deadbeef')

      result = p.call(:broadcast, tx)
      expect(result).to be_success
    end

    it 'raises ArgumentError for an unknown command' do
      p = provider.new('Limited') do |pr|
        pr.protocol chaintracks_class, base_url: 'https://ct.example.com', http_client: http_client
      end
      expect { p.call(:nonexistent_command) }.to raise_error(ArgumentError, /does not provide command :nonexistent_command/)
    end

    it 'raises ArgumentError on an empty provider' do
      p = provider.new('Empty')
      expect { p.call(:broadcast) }.to raise_error(ArgumentError, /does not provide command :broadcast/)
    end

    it 'error message includes provider name' do
      p = provider.new('MyProvider')
      expect { p.call(:missing) }.to raise_error(ArgumentError, /MyProvider/)
    end
  end

  # ── First-registered wins ─────────────────────────────────────────────────────

  describe 'first-registered-wins for duplicate commands' do
    let(:ct_response)  { fake_http_response(200, '{"height":1000}') }
    let(:woc_response) { fake_http_response(200, '{"blocks":900}') }

    let(:ct_client)  { double('ct_http_client') } # rubocop:disable RSpec/VerifiedDoubles
    let(:woc_client) { double('woc_http_client') } # rubocop:disable RSpec/VerifiedDoubles

    it 'dispatches :current_height to the first-registered protocol (Chaintracks)' do
      allow(ct_client).to receive(:request).and_return(ct_response)

      p = provider.new('Competing') do |pr|
        pr.protocol chaintracks_class, base_url: 'https://ct.example.com', http_client: ct_client
        pr.protocol woc_class, base_url: 'https://api.whatsonchain.com/v1/bsv/main', http_client: woc_client
      end

      result = p.call(:current_height)
      expect(result).to be_success
      # Chaintracks returns the height integer directly; WoCREST would return 900
      expect(result.data).to eq(1000)
    end

    it 'dispatches :current_height to WoCREST when registered first' do
      allow(woc_client).to receive(:request).and_return(woc_response)

      p = provider.new('Reversed') do |pr|
        pr.protocol woc_class,          base_url: 'https://api.whatsonchain.com/v1/bsv/main', http_client: woc_client
        pr.protocol chaintracks_class,  base_url: 'https://ct.example.com', http_client: ct_client
      end

      result = p.call(:current_height)
      expect(result).to be_success
      expect(result.data).to eq(900)
    end

    it 'stores both protocol instances when the same class is registered twice' do
      p = provider.new('Duplicate') do |pr|
        pr.protocol chaintracks_class, base_url: 'https://ct1.example.com', http_client: http_client
        pr.protocol chaintracks_class, base_url: 'https://ct2.example.com', http_client: http_client
      end
      expect(p.protocols.length).to eq(2)
    end

    it 'first instance wins in the index when same class registered twice' do
      allow(http_client).to receive(:request).and_return(ct_response)

      p = provider.new('Duplicate') do |pr|
        pr.protocol chaintracks_class, base_url: 'https://ct1.example.com', http_client: http_client
        pr.protocol chaintracks_class, base_url: 'https://ct2.example.com', http_client: http_client
      end

      # Both Chaintracks instances have the same commands; first wins in index.
      # The first has base_url ct1.example.com.
      first_instance = p.protocols.first
      expect(first_instance.base_url).to eq('https://ct1.example.com')
      # Verify dispatch hits the first instance
      result = p.call(:current_height)
      expect(result).to be_success
    end
  end

  # ── #protocol_for ─────────────────────────────────────────────────────────────

  describe '#protocol_for' do
    it 'returns the protocol instance serving the given command' do
      p = provider.new('Test') do |pr|
        pr.protocol arc_class, base_url: 'https://arc.example.com', http_client: http_client
      end
      result = p.protocol_for(:broadcast)
      expect(result).to be_a(arc_class)
    end

    it 'accepts a string command name' do
      p = provider.new('Test') do |pr|
        pr.protocol chaintracks_class, base_url: 'https://ct.example.com', http_client: http_client
      end
      expect(p.protocol_for('current_height')).to be_a(chaintracks_class)
    end

    it 'returns nil for an unknown command' do
      p = provider.new('Test') do |pr|
        pr.protocol chaintracks_class, base_url: 'https://ct.example.com', http_client: http_client
      end
      expect(p.protocol_for(:nonexistent)).to be_nil
    end

    it 'returns nil on an empty provider' do
      p = provider.new('Empty')
      expect(p.protocol_for(:broadcast)).to be_nil
    end

    it 'returns the first-registered protocol when commands overlap' do
      p = provider.new('Overlap') do |pr|
        pr.protocol chaintracks_class, base_url: 'https://ct.example.com', http_client: http_client
        pr.protocol woc_class, base_url: 'https://api.whatsonchain.com/v1/bsv/main', http_client: http_client
      end
      # :current_height is served by both; first-registered (Chaintracks) wins
      expect(p.protocol_for(:current_height)).to be_a(chaintracks_class)
    end
  end

  # ── #capability_matrix ────────────────────────────────────────────────────────

  describe '#capability_matrix' do
    it 'returns an empty hash when no protocols are registered' do
      p = provider.new('Empty')
      expect(p.capability_matrix).to eq({})
    end

    it 'maps each protocol instance to its served commands' do
      p = provider.new('Single') do |pr|
        pr.protocol chaintracks_class, base_url: 'https://ct.example.com', http_client: http_client
      end
      matrix = p.capability_matrix
      expect(matrix.keys.first).to be_a(chaintracks_class)
      expect(matrix.values.first).to eq(chaintracks_class.commands.sort)
    end

    it 'lists commands as a sorted array' do
      p = provider.new('Sorted') do |pr|
        pr.protocol chaintracks_class, base_url: 'https://ct.example.com', http_client: http_client
      end
      commands = p.capability_matrix.values.first
      expect(commands).to eq(commands.sort)
    end

    it 'respects first-registered-wins — second protocol loses overlapping commands' do
      p = provider.new('Overlap') do |pr|
        pr.protocol chaintracks_class, base_url: 'https://ct.example.com', http_client: http_client
        pr.protocol woc_class,         base_url: 'https://api.whatsonchain.com/v1/bsv/main', http_client: http_client
      end
      matrix = p.capability_matrix

      ct_instance  = p.protocols[0]
      woc_instance = p.protocols[1]

      overlap = chaintracks_class.commands & woc_class.commands

      # Chaintracks owns all its commands (including the overlapping ones)
      expect(matrix[ct_instance]).to include(*overlap.to_a)
      # WoCREST does not list the overlapping commands
      expect(matrix[woc_instance]).not_to include(*overlap.to_a)
    end

    it 'omits a protocol instance that serves no commands in this provider' do
      p = provider.new('Shadowed') do |pr|
        pr.protocol chaintracks_class, base_url: 'https://ct1.example.com', http_client: http_client
        pr.protocol chaintracks_class, base_url: 'https://ct2.example.com', http_client: http_client
      end
      matrix = p.capability_matrix
      # Second Chaintracks instance had all its commands taken by the first
      second_instance = p.protocols[1]
      expect(matrix).not_to have_key(second_instance)
    end
  end

  # ── #to_s / #inspect ──────────────────────────────────────────────────────────

  describe '#to_s' do
    it 'includes the provider name' do
      p = provider.new('GorillaPool')
      expect(p.to_s).to include('GorillaPool')
    end

    it 'includes protocol class names' do
      p = provider.new('Test') do |pr|
        pr.protocol arc_class,         base_url: 'https://arc.example.com', http_client: http_client
        pr.protocol chaintracks_class, base_url: 'https://ct.example.com',  http_client: http_client
      end
      expect(p.to_s).to include('ARC')
      expect(p.to_s).to include('Chaintracks')
    end

    it 'shows an empty protocols list when no protocols are registered' do
      p = provider.new('Empty')
      expect(p.to_s).to include('protocols=[]')
    end

    it 'shows auth=unauthenticated when no auth is configured' do
      p = provider.new('Test')
      expect(p.to_s).to include('auth=unauthenticated')
    end

    it 'shows auth=authenticated when an auth hash is supplied' do
      p = provider.new('Test', auth: { api_key: 'k' })
      expect(p.to_s).to include('auth=authenticated')
    end

    it 'omits rate_limit from output when nil' do
      p = provider.new('Test')
      expect(p.to_s).not_to include('rate_limit')
    end

    it 'includes rate_limit in output when set' do
      p = provider.new('Test', rate_limit: 10)
      expect(p.to_s).to include('rate_limit=10')
    end
  end

  describe '#inspect' do
    it 'returns the same string as #to_s' do
      p = provider.new('GorillaPool') do |pr|
        pr.protocol arc_class, base_url: 'https://arc.example.com', http_client: http_client
      end
      expect(p.inspect).to eq(p.to_s)
    end
  end
end
