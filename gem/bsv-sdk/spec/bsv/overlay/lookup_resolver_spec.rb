# frozen_string_literal: true

require 'spec_helper'
require 'bsv-sdk'

# Helpers for building test BEEF containing SLAP admin token scripts.
RESOLVER_IDENTITY_KEY_BIN = [
  '0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798'
].pack('H*')

module LookupResolverSpecHelpers
  def dummy_lock_script
    BSV::Script::Script.p2pkh_lock(("\x00" * 20).b)
  end

  # Build a PushDrop script advertising a SLAP token.
  def slap_script(domain:, service:)
    BSV::Script::Script.pushdrop_lock(
      [
        'SLAP'.b,
        RESOLVER_IDENTITY_KEY_BIN,
        domain.encode('binary'),
        service.encode('binary')
      ],
      dummy_lock_script
    )
  end

  # Build a minimal BEEF binary containing one transaction whose output at
  # index 0 is a SLAP admin token for (domain, service).
  def slap_beef(domain:, service:)
    script = slap_script(domain: domain, service: service)
    tx_out = BSV::Transaction::TransactionOutput.new(satoshis: 1, locking_script: script)
    tx     = BSV::Transaction::Tx.new
    tx.add_output(tx_out)
    beef = BSV::Transaction::Beef.new
    beef.merge_transaction(tx)
    beef.to_binary
  end

  # Build a minimal BEEF for a plain (non-SLAP) output so we can test
  # non-discovery queries.
  def plain_beef
    script = dummy_lock_script
    tx_out = BSV::Transaction::TransactionOutput.new(satoshis: 1, locking_script: script)
    tx     = BSV::Transaction::Tx.new
    tx.add_output(tx_out)
    beef = BSV::Transaction::Beef.new
    beef.merge_transaction(tx)
    beef.to_binary
  end

  # Build a LookupAnswer whose single output contains a SLAP advertisement.
  def slap_answer(domain:, service:)
    BSV::Overlay::LookupAnswer.new(
      type: 'output-list',
      outputs: [{ 'beef' => slap_beef(domain: domain, service: service), 'outputIndex' => 0 }]
    )
  end

  # Build a LookupAnswer whose single output contains a plain (non-SLAP) result.
  def plain_answer(beef_bin = nil)
    beef_bin ||= plain_beef
    BSV::Overlay::LookupAnswer.new(
      type: 'output-list',
      outputs: [{ 'beef' => beef_bin, 'outputIndex' => 0 }]
    )
  end

  def empty_answer
    BSV::Overlay::LookupAnswer.new(type: 'output-list', outputs: [])
  end

  # Stub the mock facilitator so that:
  #   - calls to the SLAP tracker return the given SLAP answer
  #   - calls to any other URL return a plain_answer (or the given default)
  def stub_slap_then_host(mock_fac, slap_tracker:, slap_resp:, host_resp: nil)
    allow(mock_fac).to receive(:lookup) do |url, _question, **_opts|
      if url == slap_tracker
        slap_resp
      else
        host_resp || plain_answer
      end
    end
  end
end

RSpec.describe 'BSV::Overlay::LookupResolver' do
  include LookupResolverSpecHelpers

  let(:mock_facilitator) do
    # Use a plain double so we can stub with block form — instance_double
    # requires exact keyword argument matching which is fragile here.
    dbl = double('LookupFacilitator') # rubocop:disable RSpec/VerifiedDoubles
    allow(dbl).to receive(:lookup).and_return(empty_answer)
    dbl
  end

  let(:slap_tracker) { 'https://mock.slap' }

  def resolver(opts = {})
    defaults = {
      facilitator: mock_facilitator,
      slap_trackers: [slap_tracker]
    }
    BSV::Overlay::LookupResolver.new(**defaults, **opts)
  end

  # ---------------------------------------------------------------------------
  # LookupFacilitator (abstract base)
  # ---------------------------------------------------------------------------

  describe BSV::Overlay::LookupFacilitator do
    it 'raises NotImplementedError on #lookup' do
      q = BSV::Overlay::LookupQuestion.new(service: 'ls_foo', query: {})
      expect { described_class.new.lookup('https://host', q) }
        .to raise_error(NotImplementedError)
    end
  end

  # ---------------------------------------------------------------------------
  # Host overrides
  # ---------------------------------------------------------------------------

  describe '#query with host_overrides' do
    it 'uses the override host and bypasses SLAP discovery' do
      result_beef = plain_beef
      allow(mock_facilitator).to receive(:lookup) do |url, _q, **_opts|
        raise 'SLAP tracker should not be queried' if url == slap_tracker

        plain_answer(result_beef)
      end

      r = resolver(host_overrides: { 'ls_foo' => ['https://override.host'] })
      answer = r.query(BSV::Overlay::LookupQuestion.new(service: 'ls_foo', query: {}))

      expect(answer.type).to eq('output-list')
      expect(answer.outputs).not_to be_empty
    end

    it 'raises ArgumentError when an override service name lacks the ls_ prefix' do
      expect do
        resolver(host_overrides: { 'bad_service' => ['https://host'] })
      end.to raise_error(ArgumentError, /ls_/)
    end
  end

  # ---------------------------------------------------------------------------
  # Additional hosts
  # ---------------------------------------------------------------------------

  describe '#query with additional_hosts' do
    it 'queries additional hosts alongside discovered hosts' do
      slap_resp = slap_answer(domain: 'discovered.host', service: 'ls_foo')
      queried_urls = []
      allow(mock_facilitator).to receive(:lookup) do |url, _q, **_opts|
        queried_urls << url
        url == slap_tracker ? slap_resp : plain_answer
      end

      r = resolver(additional_hosts: { 'ls_foo' => ['https://extra.host'] })
      r.query(BSV::Overlay::LookupQuestion.new(service: 'ls_foo', query: {}))

      expect(queried_urls).to include('https://extra.host')
    end

    it 'does not add duplicate hosts' do
      slap_resp = slap_answer(domain: 'discovered.host', service: 'ls_foo')
      queried_host_urls = []
      allow(mock_facilitator).to receive(:lookup) do |url, _q, **_opts|
        queried_host_urls << url unless url == slap_tracker
        url == slap_tracker ? slap_resp : plain_answer
      end

      r = resolver(additional_hosts: { 'ls_foo' => ['https://discovered.host'] })
      r.query(BSV::Overlay::LookupQuestion.new(service: 'ls_foo', query: {}))

      # The dedup logic prevents the same URL appearing twice in the host list
      expect(queried_host_urls.count('https://discovered.host')).to eq(1)
    end
  end

  # ---------------------------------------------------------------------------
  # SLAP tracker discovery
  # ---------------------------------------------------------------------------

  describe '#query via SLAP discovery' do
    it 'queries the discovered host after SLAP returns a valid advertisement' do
      result_beef = plain_beef
      slap_resp = slap_answer(domain: 'service.host', service: 'ls_bar')
      stub_slap_then_host(mock_facilitator, slap_tracker: slap_tracker,
                                            slap_resp: slap_resp,
                                            host_resp: plain_answer(result_beef))

      answer = resolver.query(BSV::Overlay::LookupQuestion.new(service: 'ls_bar', query: {}))
      expect(answer.type).to eq('output-list')
    end

    it 'skips SLAP outputs with wrong protocol (SHIP instead of SLAP)' do
      ship_script_val = BSV::Script::Script.pushdrop_lock(
        ['SHIP'.b, RESOLVER_IDENTITY_KEY_BIN, 'ship.host'.encode('binary'), 'ls_bar'.encode('binary')],
        BSV::Script::Script.p2pkh_lock(("\x00" * 20).b)
      )
      tx_out = BSV::Transaction::TransactionOutput.new(satoshis: 1, locking_script: ship_script_val)
      tx     = BSV::Transaction::Tx.new
      tx.add_output(tx_out)
      beef = BSV::Transaction::Beef.new
      beef.merge_transaction(tx)
      ship_answer = BSV::Overlay::LookupAnswer.new(
        type: 'output-list',
        outputs: [{ 'beef' => beef.to_binary, 'outputIndex' => 0 }]
      )

      allow(mock_facilitator).to receive(:lookup).and_return(ship_answer)

      expect do
        resolver.query(BSV::Overlay::LookupQuestion.new(service: 'ls_bar', query: {}))
      end.to raise_error(BSV::Overlay::NoCompetentHostsError)
    end

    it 'skips SLAP outputs advertising a different service' do
      slap_resp = slap_answer(domain: 'other.host', service: 'ls_other')
      allow(mock_facilitator).to receive(:lookup).and_return(slap_resp)

      expect do
        resolver.query(BSV::Overlay::LookupQuestion.new(service: 'ls_target', query: {}))
      end.to raise_error(BSV::Overlay::NoCompetentHostsError)
    end
  end

  # ---------------------------------------------------------------------------
  # ls_slap service — queries trackers directly
  # ---------------------------------------------------------------------------

  describe '#query for ls_slap service' do
    it 'queries the SLAP tracker directly without discovery' do
      received_services = []
      allow(mock_facilitator).to receive(:lookup) do |_url, question, **_opts|
        received_services << question.service
        plain_answer
      end

      r = resolver
      r.query(BSV::Overlay::LookupQuestion.new(service: 'ls_slap', query: { 'service' => 'ls_foo' }))

      # Only one lookup call expected — direct query to the tracker
      expect(received_services).to eq(['ls_slap'])
    end
  end

  # ---------------------------------------------------------------------------
  # Local preset
  # ---------------------------------------------------------------------------

  describe 'local preset' do
    it 'queries localhost:8080 without SLAP discovery' do
      queried_urls = []
      allow(mock_facilitator).to receive(:lookup) do |url, _q, **_opts|
        queried_urls << url
        plain_answer
      end

      r = BSV::Overlay::LookupResolver.new(
        network_preset: :local,
        facilitator: mock_facilitator
      )
      r.query(BSV::Overlay::LookupQuestion.new(service: 'ls_foo', query: {}))

      expect(queried_urls).to eq(['http://localhost:8080'])
    end
  end

  # ---------------------------------------------------------------------------
  # NoCompetentHostsError
  # ---------------------------------------------------------------------------

  describe 'NoCompetentHostsError' do
    it 'raises when all SLAP trackers return empty host lists' do
      allow(mock_facilitator).to receive(:lookup).and_return(empty_answer)

      expect do
        resolver.query(BSV::Overlay::LookupQuestion.new(service: 'ls_foo', query: {}))
      end.to raise_error(BSV::Overlay::NoCompetentHostsError)
    end

    it 'raises when all SLAP trackers raise errors' do
      allow(mock_facilitator).to receive(:lookup).and_raise(RuntimeError, 'Connection refused')

      expect do
        resolver.query(BSV::Overlay::LookupQuestion.new(service: 'ls_foo', query: {}))
      end.to raise_error(BSV::Overlay::NoCompetentHostsError)
    end

    it 'raises when all competent hosts fail to return a valid answer' do
      slap_resp = slap_answer(domain: 'failing.host', service: 'ls_fail')
      allow(mock_facilitator).to receive(:lookup) do |url, _q, **_opts|
        url == slap_tracker ? slap_resp : raise('timeout')
      end

      expect do
        resolver.query(BSV::Overlay::LookupQuestion.new(service: 'ls_fail', query: {}))
      end.to raise_error(BSV::Overlay::NoCompetentHostsError)
    end
  end

  # ---------------------------------------------------------------------------
  # Cache
  # ---------------------------------------------------------------------------

  describe 'host caching' do
    it 'returns cached hosts within TTL without re-querying SLAP' do
      slap_resp = slap_answer(domain: 'cached.host', service: 'ls_cached')
      slap_call_count = 0
      allow(mock_facilitator).to receive(:lookup) do |url, _q, **_opts|
        if url == slap_tracker
          slap_call_count += 1
          slap_resp
        else
          plain_answer
        end
      end

      r = resolver
      q = BSV::Overlay::LookupQuestion.new(service: 'ls_cached', query: {})
      r.query(q) # fills cache
      r.query(q) # should use cache

      expect(slap_call_count).to eq(1)
    end

    it 'revalidates cache after TTL expiry' do
      slap_resp = slap_answer(domain: 'ttl.host', service: 'ls_ttl')
      slap_call_count = 0
      allow(mock_facilitator).to receive(:lookup) do |url, _q, **_opts|
        if url == slap_tracker
          slap_call_count += 1
          slap_resp
        else
          plain_answer
        end
      end

      r = BSV::Overlay::LookupResolver.new(
        facilitator: mock_facilitator,
        slap_trackers: [slap_tracker],
        cache_ttl: 0 # expire immediately
      )
      q = BSV::Overlay::LookupQuestion.new(service: 'ls_ttl', query: {})
      r.query(q)
      r.query(q) # TTL 0 — should re-query SLAP

      expect(slap_call_count).to be >= 2
    end
  end

  # ---------------------------------------------------------------------------
  # Output deduplication
  # ---------------------------------------------------------------------------

  describe 'output deduplication' do
    it 'deduplicates outputs with the same txid.output_index across hosts' do
      shared_beef = plain_beef

      answer_a = BSV::Overlay::LookupAnswer.new(
        type: 'output-list',
        outputs: [{ 'beef' => shared_beef, 'outputIndex' => 0 }]
      )
      answer_b = BSV::Overlay::LookupAnswer.new(
        type: 'output-list',
        outputs: [{ 'beef' => shared_beef, 'outputIndex' => 0 }]
      )

      slap_resp = BSV::Overlay::LookupAnswer.new(
        type: 'output-list',
        outputs: [
          { 'beef' => slap_beef(domain: 'host-a.com', service: 'ls_dedup'), 'outputIndex' => 0 },
          { 'beef' => slap_beef(domain: 'host-b.com', service: 'ls_dedup'), 'outputIndex' => 0 }
        ]
      )

      allow(mock_facilitator).to receive(:lookup) do |url, _q, **_opts|
        case url
        when slap_tracker then slap_resp
        when 'https://host-a.com' then answer_a
        when 'https://host-b.com' then answer_b
        else empty_answer
        end
      end

      answer = resolver.query(BSV::Overlay::LookupQuestion.new(service: 'ls_dedup', query: {}))
      expect(answer.outputs.length).to eq(1)
    end
  end

  # ---------------------------------------------------------------------------
  # Reputation tracker integration
  # ---------------------------------------------------------------------------

  describe 'reputation tracker' do
    it 'records a success when a host returns a valid answer' do
      slap_resp = slap_answer(domain: 'good.host', service: 'ls_rep')
      stub_slap_then_host(mock_facilitator, slap_tracker: slap_tracker, slap_resp: slap_resp)

      success_hosts = []
      rep = instance_double(BSV::Overlay::HostReputationTracker)
      allow(rep).to receive(:rank_hosts) { |hosts| hosts }
      allow(rep).to receive(:record_success) { |host, _lat| success_hosts << host }
      allow(rep).to receive(:record_failure)

      r = BSV::Overlay::LookupResolver.new(
        facilitator: mock_facilitator,
        slap_trackers: [slap_tracker],
        reputation_tracker: rep
      )
      r.query(BSV::Overlay::LookupQuestion.new(service: 'ls_rep', query: {}))

      expect(success_hosts).to include('https://good.host')
    end

    it 'records a failure when a host raises an error' do
      slap_resp = slap_answer(domain: 'bad.host', service: 'ls_rep')
      allow(mock_facilitator).to receive(:lookup) do |url, _q, **_opts|
        url == slap_tracker ? slap_resp : raise('timeout')
      end

      failure_hosts = []
      rep = instance_double(BSV::Overlay::HostReputationTracker)
      allow(rep).to receive(:rank_hosts) { |hosts| hosts }
      allow(rep).to receive(:record_success)
      allow(rep).to receive(:record_failure) { |host, _err| failure_hosts << host }

      r = BSV::Overlay::LookupResolver.new(
        facilitator: mock_facilitator,
        slap_trackers: [slap_tracker],
        reputation_tracker: rep
      )
      expect do
        r.query(BSV::Overlay::LookupQuestion.new(service: 'ls_rep', query: {}))
      end.to raise_error(BSV::Overlay::NoCompetentHostsError)

      expect(failure_hosts).to include('https://bad.host')
    end
  end

  # ---------------------------------------------------------------------------
  # Constructor validation
  # ---------------------------------------------------------------------------

  describe 'constructor validation' do
    it 'raises ArgumentError for additional_hosts without ls_ prefix' do
      expect do
        resolver(additional_hosts: { 'nope' => ['https://host'] })
      end.to raise_error(ArgumentError, /ls_/)
    end

    it 'raises ArgumentError for host_overrides without ls_ prefix' do
      expect do
        resolver(host_overrides: { 'nope' => ['https://host'] })
      end.to raise_error(ArgumentError, /ls_/)
    end

    it 'raises ArgumentError when slap_trackers is empty for mainnet' do
      expect do
        BSV::Overlay::LookupResolver.new(
          facilitator: mock_facilitator,
          slap_trackers: []
        )
      end.to raise_error(ArgumentError, /slap_trackers/)
    end
  end

  # ---------------------------------------------------------------------------
  # SSRF protection
  # ---------------------------------------------------------------------------

  describe 'SSRF protection' do
    it 'rejects SLAP advertisements with loopback IP domains' do
      beef = slap_beef(domain: '127.0.0.1', service: 'ls_ssrf')
      answer = BSV::Overlay::LookupAnswer.new(
        type: 'output-list',
        outputs: [{ 'beef' => beef, 'outputIndex' => 0 }]
      )

      allow(mock_facilitator).to receive(:lookup) { |url, _q, **_opts|
        if url == slap_tracker
          answer
        else
          BSV::Overlay::LookupAnswer.new(type: 'output-list', outputs: [])
        end
      }

      r = resolver
      expect do
        r.query(BSV::Overlay::LookupQuestion.new(service: 'ls_ssrf', query: {}))
      end.to raise_error(BSV::Overlay::NoCompetentHostsError)
    end

    it 'rejects SLAP advertisements with private IP domains' do
      %w[10.0.0.1 192.168.1.1 172.16.0.1].each do |ip|
        beef = slap_beef(domain: ip, service: 'ls_priv')
        answer = BSV::Overlay::LookupAnswer.new(
          type: 'output-list',
          outputs: [{ 'beef' => beef, 'outputIndex' => 0 }]
        )

        allow(mock_facilitator).to receive(:lookup) { |url, _q, **_opts|
          if url == slap_tracker
            answer
          else
            BSV::Overlay::LookupAnswer.new(type: 'output-list', outputs: [])
          end
        }

        r = resolver
        expect do
          r.query(BSV::Overlay::LookupQuestion.new(service: 'ls_priv', query: {}))
        end.to raise_error(BSV::Overlay::NoCompetentHostsError)
      end
    end

    it 'rejects SLAP advertisements with link-local IP domains' do
      beef = slap_beef(domain: '169.254.169.254', service: 'ls_meta')
      answer = BSV::Overlay::LookupAnswer.new(
        type: 'output-list',
        outputs: [{ 'beef' => beef, 'outputIndex' => 0 }]
      )

      allow(mock_facilitator).to receive(:lookup) { |url, _q, **_opts|
        if url == slap_tracker
          answer
        else
          BSV::Overlay::LookupAnswer.new(type: 'output-list', outputs: [])
        end
      }

      r = resolver
      expect do
        r.query(BSV::Overlay::LookupQuestion.new(service: 'ls_meta', query: {}))
      end.to raise_error(BSV::Overlay::NoCompetentHostsError)
    end
  end
end
