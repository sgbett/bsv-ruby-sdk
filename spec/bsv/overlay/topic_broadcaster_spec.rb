# frozen_string_literal: true

require 'spec_helper'
require 'bsv-sdk'

# Build a minimal AdmittanceInstructions representing a positive acknowledgement.
def ack_instructions(outputs: [0])
  BSV::Overlay::AdmittanceInstructions.new(
    outputs_to_admit: outputs,
    coins_to_retain: [],
    coins_removed: nil
  )
end

# Build an AdmittanceInstructions that represents no acknowledgement.
def no_ack_instructions
  BSV::Overlay::AdmittanceInstructions.new(
    outputs_to_admit: [],
    coins_to_retain: [],
    coins_removed: nil
  )
end

RSpec.describe BSV::Overlay::TopicBroadcaster do
  # ---- Shared doubles ----

  # A mock transaction that serialises successfully and has a stable txid.
  let(:mock_txid) { "#{'aabbcc' * 10}aabb" }

  let(:mock_tx) do
    tx = instance_double(BSV::Transaction::Transaction)
    allow(tx).to receive_messages(to_beef: "\xbe\xef\x01", txid: mock_txid)
    tx
  end

  # A facilitator that records calls and returns configurable STEAKs.
  let(:mock_facilitator) do
    dbl = instance_double(BSV::Overlay::BroadcastFacilitator)
    allow(dbl).to receive(:send_beef) do |_url, tagged_beef|
      # Return acks for every topic in the tagged beef by default
      tagged_beef.topics.to_h { |t| [t, ack_instructions] }
    end
    dbl
  end

  # A resolver that returns a single host interested in all topics.
  def mock_resolver_for(_host_topics_map)
    dbl = instance_double(BSV::Overlay::LookupResolver)
    allow(dbl).to receive(:query) do |_question|
      # Return an output-list answer; the broadcaster parses SHIP admin tokens
      # from these outputs, but in tests we bypass that by supplying a
      # pre-built resolver that returns no outputs — host discovery uses
      # fetch_ship_hosts which falls back on the raw answer outputs.
      # Instead, we inject hosts via a custom resolver.
      BSV::Overlay::LookupAnswer.new(type: 'output-list', outputs: [])
    end

    # Monkey-patch find_interested_hosts to return the provided map directly.
    # We achieve this by making the broadcaster accept the map from a stub.
    dbl
  end

  # Build a broadcaster with injected host map (bypasses SHIP parsing).
  def broadcaster_with_hosts(topics, host_topics_map, **opts)
    broadcaster = described_class.new(
      topics,
      facilitator: mock_facilitator,
      resolver: instance_double(BSV::Overlay::LookupResolver),
      **opts
    )
    allow(broadcaster).to receive(:find_interested_hosts).and_return(host_topics_map)
    broadcaster
  end

  # ---- Constructor validation ----

  describe 'topic validation' do
    it 'raises ArgumentError for an empty topics array' do
      expect { described_class.new([]) }
        .to raise_error(ArgumentError, /non-empty/)
    end

    it 'raises ArgumentError for nil topics' do
      expect { described_class.new(nil) }
        .to raise_error(ArgumentError, /non-empty/)
    end

    it 'raises ArgumentError for a topic without tm_ prefix' do
      expect { described_class.new(['nope_topic']) }
        .to raise_error(ArgumentError, /tm_/)
    end

    it 'accepts valid tm_ prefixed topics' do
      expect { described_class.new(['tm_valid']) }.not_to raise_error
    end
  end

  # ---- Successful broadcast ----

  describe '#broadcast — single host, single topic' do
    subject(:broadcaster) do
      broadcaster_with_hosts(['tm_foo'], { 'https://host1.example.com' => Set.new(['tm_foo']) })
    end

    it 'returns an OverlayBroadcastResult' do
      result = broadcaster.broadcast(mock_tx)
      expect(result).to be_a(BSV::Overlay::OverlayBroadcastResult)
    end

    it 'returns status success' do
      result = broadcaster.broadcast(mock_tx)
      expect(result.status).to eq('success')
    end

    it 'includes the transaction txid' do
      result = broadcaster.broadcast(mock_tx)
      expect(result.txid).to eq(mock_txid)
    end

    it 'includes a human-readable message with host count' do
      result = broadcaster.broadcast(mock_tx)
      expect(result.message).to match(/1 Overlay Service host/)
    end
  end

  describe '#broadcast — multiple hosts with disjoint topics' do
    subject(:broadcaster) do
      broadcaster_with_hosts(
        topics,
        host_map,
        require_ack_from_any_host: 'any'
      )
    end

    let(:topics) { %w[tm_foo tm_bar] }
    let(:host_map) do
      {
        'https://host1.example.com' => Set.new(['tm_foo']),
        'https://host2.example.com' => Set.new(['tm_bar'])
      }
    end

    let(:sent) { {} }

    before do
      # Track which topics each host received
      allow(mock_facilitator).to receive(:send_beef) do |url, tagged_beef|
        sent[url] = tagged_beef.topics.dup
        tagged_beef.topics.to_h { |t| [t, ack_instructions] }
      end
    end

    it 'sends only matching topics to each host' do
      broadcaster.broadcast(mock_tx)
      expect(sent['https://host1.example.com']).to eq(['tm_foo'])
      expect(sent['https://host2.example.com']).to eq(['tm_bar'])
    end

    it 'returns success when at least one host acknowledges a topic' do
      result = broadcaster.broadcast(mock_tx)
      expect(result.status).to eq('success')
    end
  end

  # ---- Error cases ----

  describe '#broadcast — no hosts interested' do
    subject(:broadcaster) do
      broadcaster_with_hosts(['tm_foo'], {})
    end

    it 'returns ERR_NO_HOSTS_INTERESTED' do
      result = broadcaster.broadcast(mock_tx)
      expect(result.status).to eq('error')
      expect(result.code).to eq('ERR_NO_HOSTS_INTERESTED')
    end
  end

  describe '#broadcast — all hosts reject' do
    subject(:broadcaster) do
      b = broadcaster_with_hosts(
        ['tm_foo'],
        { 'https://host1.example.com' => Set.new(['tm_foo']) }
      )
      allow(mock_facilitator).to receive(:send_beef).and_return(nil)
      b
    end

    it 'returns ERR_ALL_HOSTS_REJECTED' do
      result = broadcaster.broadcast(mock_tx)
      expect(result.status).to eq('error')
      expect(result.code).to eq('ERR_ALL_HOSTS_REJECTED')
    end
  end

  describe '#broadcast — BEEF serialisation failure' do
    subject(:broadcaster) do
      broadcaster_with_hosts(
        ['tm_foo'],
        { 'https://host1.example.com' => Set.new(['tm_foo']) }
      )
    end

    before { allow(mock_tx).to receive(:to_beef).and_raise(StandardError, 'no inputs') }

    it 'returns an error result without raising' do
      result = broadcaster.broadcast(mock_tx)
      expect(result.status).to eq('error')
      expect(result.description).to match(/no inputs/)
    end
  end

  # ---- Local preset ----

  describe 'local network preset' do
    subject(:broadcaster) do
      described_class.new(
        ['tm_foo'],
        network_preset: :local,
        facilitator: mock_facilitator,
        resolver: instance_double(BSV::Overlay::LookupResolver)
      )
    end

    it 'broadcasts to localhost:8080 without querying resolver' do
      called_urls = []
      allow(mock_facilitator).to receive(:send_beef) do |url, tagged_beef|
        called_urls << url
        tagged_beef.topics.to_h { |t| [t, ack_instructions] }
      end
      broadcaster.broadcast(mock_tx)
      expect(called_urls).to eq(['http://localhost:8080'])
    end
  end

  # ---- Acknowledgement requirements ----

  describe 'require_ack_from_any_host: "all" (default)' do
    subject(:broadcaster) do
      broadcaster_with_hosts(
        %w[tm_foo tm_bar],
        {
          'https://host1.example.com' => Set.new(%w[tm_foo tm_bar]),
          'https://host2.example.com' => Set.new(%w[tm_foo tm_bar])
        }
      )
    end

    it 'succeeds when at least one host acknowledges all topics' do
      # host1 acks both, host2 acks neither
      call_count = 0
      allow(mock_facilitator).to receive(:send_beef) do |_url, tagged_beef|
        call_count += 1
        if call_count == 1
          # First host acks all topics
          tagged_beef.topics.to_h { |t| [t, ack_instructions] }
        else
          # Second host acks nothing
          tagged_beef.topics.to_h { |t| [t, no_ack_instructions] }
        end
      end

      result = broadcaster.broadcast(mock_tx)
      expect(result.status).to eq('success')
    end

    it 'fails when no host acknowledges all topics' do
      allow(mock_facilitator).to receive(:send_beef) do |_url, tagged_beef|
        # Each host only acks one topic
        { tagged_beef.topics.first => ack_instructions }
      end

      result = broadcaster.broadcast(mock_tx)
      expect(result.status).to eq('error')
      expect(result.code).to eq('ERR_REQUIRE_ACK_FROM_ANY_HOST_FAILED')
    end
  end

  describe 'require_ack_from_any_host: "any"' do
    subject(:broadcaster) do
      broadcaster_with_hosts(
        %w[tm_foo tm_bar],
        { 'https://host1.example.com' => Set.new(%w[tm_foo tm_bar]) },
        require_ack_from_any_host: 'any'
      )
    end

    it 'succeeds when a host acknowledges at least one topic' do
      allow(mock_facilitator).to receive(:send_beef) do |_url, tagged_beef|
        { tagged_beef.topics.first => ack_instructions }
      end

      result = broadcaster.broadcast(mock_tx)
      expect(result.status).to eq('success')
    end
  end

  describe 'require_ack_from_all_hosts: "all"' do
    subject(:broadcaster) do
      broadcaster_with_hosts(
        %w[tm_foo tm_bar],
        {
          'https://host1.example.com' => Set.new(%w[tm_foo tm_bar]),
          'https://host2.example.com' => Set.new(%w[tm_foo tm_bar])
        },
        require_ack_from_all_hosts: 'all',
        require_ack_from_any_host: 'any'
      )
    end

    it 'fails when one host does not acknowledge all topics' do
      call_count = 0
      allow(mock_facilitator).to receive(:send_beef) do |_url, tagged_beef|
        call_count += 1
        if call_count == 1
          tagged_beef.topics.to_h { |t| [t, ack_instructions] }
        else
          # Second host only acknowledges one topic
          { 'tm_foo' => ack_instructions }
        end
      end

      result = broadcaster.broadcast(mock_tx)
      expect(result.status).to eq('error')
      expect(result.code).to eq('ERR_REQUIRE_ACK_FROM_ALL_HOSTS_FAILED')
    end

    it 'succeeds when all hosts acknowledge all topics' do
      allow(mock_facilitator).to receive(:send_beef) do |_url, tagged_beef|
        tagged_beef.topics.to_h { |t| [t, ack_instructions] }
      end

      result = broadcaster.broadcast(mock_tx)
      expect(result.status).to eq('success')
    end
  end

  describe 'require_ack_from_specific_hosts' do
    subject(:broadcaster) do
      broadcaster_with_hosts(
        ['tm_foo'],
        {
          required_host => Set.new(['tm_foo']),
          'https://other.example.com' => Set.new(['tm_foo'])
        },
        require_ack_from_specific_hosts: { required_host => 'all' },
        require_ack_from_any_host: 'any'
      )
    end

    let(:required_host) { 'https://required.example.com' }

    it 'fails when the required host does not acknowledge' do
      allow(mock_facilitator).to receive(:send_beef) do |url, tagged_beef|
        if url == required_host
          { 'tm_foo' => no_ack_instructions }
        else
          tagged_beef.topics.to_h { |t| [t, ack_instructions] }
        end
      end

      result = broadcaster.broadcast(mock_tx)
      expect(result.status).to eq('error')
      expect(result.code).to eq('ERR_REQUIRE_ACK_FROM_SPECIFIC_HOSTS_FAILED')
    end

    it 'fails when the required host did not respond at all' do
      allow(mock_facilitator).to receive(:send_beef) do |url, tagged_beef|
        if url == required_host
          nil # Host rejected / did not respond
        else
          tagged_beef.topics.to_h { |t| [t, ack_instructions] }
        end
      end

      result = broadcaster.broadcast(mock_tx)
      expect(result.status).to eq('error')
      expect(result.code).to eq('ERR_REQUIRE_ACK_FROM_SPECIFIC_HOSTS_FAILED')
    end

    it 'succeeds when the required host acknowledges' do
      result = broadcaster.broadcast(mock_tx)
      expect(result.status).to eq('success')
    end
  end

  # ---- SHIPBroadcaster alias ----

  describe 'SHIPBroadcaster alias' do
    it 'is the same class as TopicBroadcaster' do
      expect(BSV::Overlay::SHIPBroadcaster).to equal(described_class)
    end

    it 'can be instantiated as SHIPBroadcaster' do
      broadcaster = BSV::Overlay::SHIPBroadcaster.new(
        ['tm_test'],
        network_preset: :local,
        facilitator: mock_facilitator,
        resolver: instance_double(BSV::Overlay::LookupResolver)
      )
      expect(broadcaster).to be_a(described_class)
    end
  end
end
