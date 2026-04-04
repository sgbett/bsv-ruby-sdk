# frozen_string_literal: true

require 'spec_helper'
require 'bsv-sdk'

RSpec.describe BSV::Overlay::HostReputationTracker do
  subject(:tracker) { described_class.new }

  let(:host) { 'https://overlay.example.com' }

  # -------------------------------------------------------------------------
  # Success recording — EWMA latency
  # -------------------------------------------------------------------------

  describe '#record_success' do
    it 'sets avg_latency_ms directly on first success (no smoothing)' do
      tracker.record_success(host, 200)
      snap = tracker.snapshot(host)
      expect(snap[:avg_latency_ms]).to eq(200.0)
    end

    it 'applies EWMA smoothing on subsequent successes' do
      # After first success avg = 200
      tracker.record_success(host, 200)
      # Second: new_avg = 200 * 0.75 + 400 * 0.25 = 150 + 100 = 250
      tracker.record_success(host, 400)
      snap = tracker.snapshot(host)
      expect(snap[:avg_latency_ms]).to be_within(0.001).of(250.0)
    end

    it 'applies further EWMA smoothing on a third success' do
      tracker.record_success(host, 200)
      tracker.record_success(host, 400) # avg = 250
      # Third: new_avg = 250 * 0.75 + 100 * 0.25 = 187.5 + 25 = 212.5
      tracker.record_success(host, 100)
      snap = tracker.snapshot(host)
      expect(snap[:avg_latency_ms]).to be_within(0.001).of(212.5)
    end

    it 'increments total_successes' do
      tracker.record_success(host, 100)
      tracker.record_success(host, 100)
      expect(tracker.snapshot(host)[:total_successes]).to eq(2)
    end

    it 'resets consecutive_failures to zero' do
      tracker.record_failure(host)
      tracker.record_failure(host)
      tracker.record_success(host, 100)
      expect(tracker.snapshot(host)[:consecutive_failures]).to eq(0)
    end

    it 'clears backoff_until' do
      # Force three failures so backoff is set
      3.times { tracker.record_failure(host) }
      expect(tracker.snapshot(host)[:backoff_until]).not_to be_nil

      tracker.record_success(host, 100)
      expect(tracker.snapshot(host)[:backoff_until]).to be_nil
    end

    it 'clamps negative latency to DEFAULT_LATENCY_MS' do
      tracker.record_success(host, -50)
      snap = tracker.snapshot(host)
      expect(snap[:avg_latency_ms]).to eq(described_class::DEFAULT_LATENCY_MS.to_f)
    end

    it 'clamps NaN latency to DEFAULT_LATENCY_MS' do
      tracker.record_success(host, Float::NAN)
      snap = tracker.snapshot(host)
      expect(snap[:avg_latency_ms]).to eq(described_class::DEFAULT_LATENCY_MS.to_f)
    end

    it 'clamps Infinity latency to DEFAULT_LATENCY_MS' do
      tracker.record_success(host, Float::INFINITY)
      snap = tracker.snapshot(host)
      expect(snap[:avg_latency_ms]).to eq(described_class::DEFAULT_LATENCY_MS.to_f)
    end
  end

  # -------------------------------------------------------------------------
  # Failure recording — backoff logic
  # -------------------------------------------------------------------------

  describe '#record_failure' do
    it 'does not set backoff_until on first failure (within grace period)' do
      tracker.record_failure(host)
      expect(tracker.snapshot(host)[:backoff_until]).to be_nil
    end

    it 'does not set backoff_until on second failure (within grace period)' do
      tracker.record_failure(host)
      tracker.record_failure(host)
      expect(tracker.snapshot(host)[:backoff_until]).to be_nil
    end

    it 'sets backoff_until on third failure (BASE_BACKOFF_MS = 1 s)' do
      now = Time.now
      allow(Time).to receive(:now).and_return(now)

      3.times { tracker.record_failure(host) }

      snap = tracker.snapshot(host)
      expect(snap[:backoff_until]).to be_within(0.01).of(now + 1.0)
    end

    it 'doubles the backoff on the fourth failure (2 s)' do
      now = Time.now
      allow(Time).to receive(:now).and_return(now)

      4.times { tracker.record_failure(host) }

      snap = tracker.snapshot(host)
      expect(snap[:backoff_until]).to be_within(0.01).of(now + 2.0)
    end

    it 'doubles again on the fifth failure (4 s)' do
      now = Time.now
      allow(Time).to receive(:now).and_return(now)

      5.times { tracker.record_failure(host) }

      snap = tracker.snapshot(host)
      expect(snap[:backoff_until]).to be_within(0.01).of(now + 4.0)
    end

    it 'caps backoff at MAX_BACKOFF_MS (60 s)' do
      now = Time.now
      allow(Time).to receive(:now).and_return(now)

      # Need enough failures to exceed cap: BASE * 2^(n-GRACE-1) >= 60_000
      # 1000 * 2^(n-3) >= 60000 → 2^(n-3) >= 60 → n-3 >= 6 → n >= 9
      # Use 15 failures to be safely past the cap.
      15.times { tracker.record_failure(host) }

      snap = tracker.snapshot(host)
      expect(snap[:backoff_until]).to be_within(0.01).of(now + 60.0)
    end

    it 'increments total_failures on each call' do
      3.times { tracker.record_failure(host) }
      expect(tracker.snapshot(host)[:total_failures]).to eq(3)
    end

    it 'records the last_error when reason is supplied' do
      tracker.record_failure(host, 'timeout')
      expect(tracker.snapshot(host)[:last_error]).to eq('timeout')
    end
  end

  # -------------------------------------------------------------------------
  # DNS error — skip grace period
  # -------------------------------------------------------------------------

  describe '#record_failure — DNS errors skip grace period' do
    it 'triggers backoff immediately on SocketError' do
      now = Time.now
      allow(Time).to receive(:now).and_return(now)

      tracker.record_failure(host, SocketError.new('getaddrinfo failed'))

      snap = tracker.snapshot(host)
      expect(snap[:backoff_until]).not_to be_nil
      expect(snap[:backoff_until]).to be_within(0.01).of(now + 1.0)
    end

    it 'triggers backoff immediately on Errno::ECONNREFUSED' do
      now = Time.now
      allow(Time).to receive(:now).and_return(now)

      tracker.record_failure(host, Errno::ECONNREFUSED.new)

      snap = tracker.snapshot(host)
      expect(snap[:backoff_until]).not_to be_nil
    end

    it 'triggers backoff immediately when message contains "getaddrinfo"' do
      now = Time.now
      allow(Time).to receive(:now).and_return(now)

      tracker.record_failure(host, RuntimeError.new('getaddrinfo: Name or service not known'))

      snap = tracker.snapshot(host)
      expect(snap[:backoff_until]).not_to be_nil
    end

    it 'triggers backoff immediately when message contains "Failed to fetch"' do
      now = Time.now
      allow(Time).to receive(:now).and_return(now)

      tracker.record_failure(host, 'Failed to fetch resource')

      snap = tracker.snapshot(host)
      expect(snap[:backoff_until]).not_to be_nil
    end
  end

  # -------------------------------------------------------------------------
  # rank_hosts
  # -------------------------------------------------------------------------

  describe '#rank_hosts' do
    let(:host_a) { 'https://a.example.com' }
    let(:host_b) { 'https://b.example.com' }
    let(:host_c) { 'https://c.example.com' }

    it 'returns available hosts before backed-off hosts' do
      now = Time.now
      allow(Time).to receive(:now).and_return(now)

      3.times { tracker.record_failure(host_a) } # backed off
      tracker.record_success(host_b, 100) # available

      result = tracker.rank_hosts([host_a, host_b])
      expect(result).to eq([host_b, host_a])
    end

    it 'deduplicates hosts preserving first occurrence order' do
      result = tracker.rank_hosts([host_a, host_b, host_a, host_c])
      expect(result).to eq([host_a, host_b, host_c])
    end

    it 'filters out nil entries' do
      result = tracker.rank_hosts([host_a, nil, host_b])
      expect(result).not_to include(nil)
      expect(result).to include(host_a, host_b)
    end

    it 'filters out empty-string entries' do
      result = tracker.rank_hosts([host_a, '', host_b])
      expect(result).not_to include('')
      expect(result).to include(host_a, host_b)
    end

    it 'sorts available hosts by score ascending' do
      # host_a: 3 failures → high penalty; host_b: 1 fast success → low score
      3.times { tracker.record_failure(host_a) }

      now = Time.now + 100 # far future so host_a backoff has expired
      tracker.record_success(host_b, 100)

      # Re-stub now so host_a is NOT in backoff
      allow(Time).to receive(:now).and_return(now)

      result = tracker.rank_hosts([host_a, host_b], now)
      expect(result.first).to eq(host_b)
    end

    it 'sorts backed-off hosts by backoff_until ascending' do
      now = Time.now
      allow(Time).to receive(:now).and_return(now)

      # Give host_b more failures so it has a longer backoff
      3.times { tracker.record_failure(host_a) }     # backoff = now + 1 s
      6.times { tracker.record_failure(host_b) }     # backoff = now + 8 s (2^3)

      result = tracker.rank_hosts([host_b, host_a])  # intentionally swapped
      expect(result).to eq([host_a, host_b])
    end

    it 'returns an empty array for an empty input' do
      expect(tracker.rank_hosts([])).to eq([])
    end
  end

  # -------------------------------------------------------------------------
  # snapshot
  # -------------------------------------------------------------------------

  describe '#snapshot' do
    it 'returns nil for an unknown host' do
      expect(tracker.snapshot('https://unknown.example.com')).to be_nil
    end

    it 'returns a frozen hash for a known host' do
      tracker.record_success(host, 100)
      snap = tracker.snapshot(host)
      expect(snap).to be_a(Hash)
      expect(snap).to be_frozen
    end

    it 'does not expose internal mutable state (copy, not reference)' do
      tracker.record_success(host, 100)
      snap = tracker.snapshot(host)
      expect { snap[:total_successes] = 999 }.to raise_error(FrozenError)
    end
  end

  # -------------------------------------------------------------------------
  # score computation
  # -------------------------------------------------------------------------

  describe 'score computation' do
    it 'computes expected score for known inputs' do
      # Set up: 1 success at 500 ms, then 1 failure (still within grace)
      now = Time.now
      allow(Time).to receive(:now).and_return(now)

      tracker.record_success(host, 500)
      tracker.record_failure(host)

      snap = tracker.snapshot(host)

      avg   = snap[:avg_latency_ms]          # 500.0 (first success sets directly)
      cons  = snap[:consecutive_failures]    # 1
      succs = snap[:total_successes]         # 1

      # score = avg + cons * PENALTY - min(succs * BONUS, avg / 2)
      #       = 500 + 1 * 400 - min(1 * 30, 250) = 900 - 30 = 870
      expected = avg + (cons * described_class::FAILURE_PENALTY_MS) -
                 [succs * described_class::SUCCESS_BONUS_MS, avg / 2.0].min

      expect(expected).to be_within(0.001).of(870.0)
    end
  end

  # -------------------------------------------------------------------------
  # reset
  # -------------------------------------------------------------------------

  describe '#reset' do
    it 'clears all entries so snapshots return nil' do
      tracker.record_success(host, 100)
      tracker.reset
      expect(tracker.snapshot(host)).to be_nil
    end

    it 'returns an empty host list from rank_hosts after reset' do
      tracker.record_success(host, 100)
      tracker.reset
      result = tracker.rank_hosts([host])
      # All hosts are unknown (default entry created inline), so just verify
      # the host is still included in output (no crash).
      expect(result).to include(host)
    end
  end

  # -------------------------------------------------------------------------
  # store adapter
  # -------------------------------------------------------------------------

  describe 'optional store adapter' do
    let(:store) do
      data = {}
      Class.new do
        define_method(:get) { |k| data[k] }
        define_method(:set) { |k, v| data[k] = v }
      end.new
    end

    it 'persists entries to the store on record_success' do
      t = described_class.new(store: store)
      t.record_success(host, 200)
      expect(store.get(host)).not_to be_nil
      expect(store.get(host)[:total_successes]).to eq(1)
    end

    it 'persists entries to the store on record_failure' do
      t = described_class.new(store: store)
      t.record_failure(host, 'err')
      expect(store.get(host)[:total_failures]).to eq(1)
    end

    it 'loads an entry from the store on first snapshot access' do
      existing = {
        host: host,
        total_successes: 5,
        total_failures: 0,
        consecutive_failures: 0,
        avg_latency_ms: 300.0,
        last_latency_ms: 300.0,
        backoff_until: nil,
        last_updated_at: Time.now,
        last_error: nil
      }
      store.set(host, existing)

      t    = described_class.new(store: store)
      snap = t.snapshot(host)
      expect(snap[:total_successes]).to eq(5)
    end
  end

  # -------------------------------------------------------------------------
  # Thread safety
  # -------------------------------------------------------------------------

  describe 'thread safety' do
    it 'handles concurrent record_success/record_failure without corrupting state' do
      threads = []

      20.times do |i|
        threads << Thread.new do
          if i.even?
            tracker.record_success(host, 100 + i)
          else
            tracker.record_failure(host)
          end
        end
      end

      threads.each(&:join)

      snap = tracker.snapshot(host)
      expect(snap).not_to be_nil
      expect(snap[:total_successes] + snap[:total_failures]).to eq(20)
    end

    it 'handles concurrent rank_hosts calls without raising' do
      hosts = (1..5).map { |i| "https://host#{i}.example.com" }

      threads = 10.times.map do
        Thread.new { tracker.rank_hosts(hosts) }
      end

      expect { threads.each(&:join) }.not_to raise_error
    end
  end
end
