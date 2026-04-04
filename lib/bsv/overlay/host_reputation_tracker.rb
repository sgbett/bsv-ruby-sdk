# frozen_string_literal: true

module BSV
  module Overlay
    # Tracks per-host reputation for overlay query dispatch.
    #
    # Records success and failure events per host, maintains an EWMA latency
    # estimate, applies exponential backoff after repeated failures, and ranks
    # a candidate host list so callers can prefer fast, reliable hosts.
    #
    # Thread-safe via an internal Mutex.
    #
    # An optional +store+ adapter may be supplied for persistence. The adapter
    # must respond to +#get(key)+ and +#set(key, value)+. When provided, each
    # updated entry is persisted and unknown hosts are loaded on first access.
    class HostReputationTracker
      # Fallback latency used when no measurements exist yet, or when an
      # invalid (negative / non-finite) value is reported.
      DEFAULT_LATENCY_MS = 1500

      # EWMA smoothing factor (α). Higher values give more weight to recent
      # observations; lower values produce a smoother, more stable estimate.
      LATENCY_SMOOTHING_FACTOR = 0.25

      # Starting backoff duration in milliseconds.
      BASE_BACKOFF_MS = 1000

      # Maximum backoff duration in milliseconds (60 seconds).
      MAX_BACKOFF_MS = 60_000

      # Latency penalty added to a host's score per consecutive failure.
      FAILURE_PENALTY_MS = 400

      # Latency bonus subtracted from a host's score per recorded success,
      # capped at half the current average latency.
      SUCCESS_BONUS_MS = 30

      # Number of consecutive failures that are forgiven before backoff kicks
      # in. A host may fail this many times without being penalised with a
      # backoff window.
      FAILURE_BACKOFF_GRACE = 2

      # @param store [#get, #set, nil] optional persistence adapter
      def initialize(store: nil)
        @entries = {}
        @mutex   = Mutex.new
        @store   = store
      end

      # Records a successful request to +host+.
      #
      # Updates the EWMA latency estimate (first success sets the average
      # directly; subsequent successes apply smoothing). Resets consecutive
      # failure count and clears any active backoff window.
      #
      # @param host       [String]  hostname or URL
      # @param latency_ms [Numeric] observed round-trip time in milliseconds
      def record_success(host, latency_ms)
        @mutex.synchronize do
          entry = fetch_or_create(host)

          safe_latency = valid_latency?(latency_ms) ? latency_ms.to_f : DEFAULT_LATENCY_MS.to_f

          entry[:avg_latency_ms] =
            if entry[:total_successes].zero?
              safe_latency
            else
              (entry[:avg_latency_ms] * (1 - LATENCY_SMOOTHING_FACTOR)) + (safe_latency * LATENCY_SMOOTHING_FACTOR)
            end

          entry[:last_latency_ms] = safe_latency
          entry[:total_successes] += 1
          entry[:consecutive_failures] = 0
          entry[:backoff_until]        = nil
          entry[:last_updated_at]      = Time.now

          persist(host, entry)
        end
      end

      # Records a failed request to +host+.
      #
      # Increments failure counters. Once consecutive failures exceed
      # +FAILURE_BACKOFF_GRACE+, an exponential backoff window is set.
      #
      # DNS-level errors (+SocketError+, +Errno::ECONNREFUSED+, or messages
      # containing 'getaddrinfo' or 'Failed to fetch') skip the grace period
      # entirely — backoff is applied from the very first such failure.
      #
      # @param host   [String]            hostname or URL
      # @param reason [Exception, String, nil] error that caused the failure
      def record_failure(host, reason = nil)
        @mutex.synchronize do
          entry = fetch_or_create(host)
          now   = Time.now

          entry[:total_failures] += 1
          entry[:last_error]      = reason.to_s if reason
          entry[:last_updated_at] = now

          if dns_error?(reason)
            # Skip grace period but continue ramping — ensure consecutive_failures
            # is at least past grace, then keep incrementing on repeated DNS errors.
            entry[:consecutive_failures] = [entry[:consecutive_failures] + 1, FAILURE_BACKOFF_GRACE + 1].max
          else
            entry[:consecutive_failures] += 1
          end

          consecutive = entry[:consecutive_failures]

          if consecutive > FAILURE_BACKOFF_GRACE
            exponent   = consecutive - FAILURE_BACKOFF_GRACE - 1
            backoff_ms = [BASE_BACKOFF_MS * (2**exponent), MAX_BACKOFF_MS].min
            entry[:backoff_until] = now + (backoff_ms / 1000.0)
          end

          persist(host, entry)
        end
      end

      # Ranks +hosts+ for query dispatch.
      #
      # Steps:
      # 1. Filter nil and empty-string entries.
      # 2. Deduplicate preserving first occurrence order.
      # 3. Compute a score for each host.
      # 4. Sort: available hosts first (score asc, then total_successes desc,
      #    then original position asc), followed by backed-off hosts
      #    (backoff_until asc).
      #
      # @param hosts [Array<String>] candidate host list
      # @param now   [Time]          reference time (default: Time.now)
      # @return [Array<String>]
      def rank_hosts(hosts, now = Time.now)
        @mutex.synchronize do
          filtered  = hosts.select { |h| h.is_a?(String) && !h.empty? }
          unique    = deduplicate(filtered)

          available = []
          backed_off = []

          unique.each_with_index do |host, idx|
            entry = fetch_or_create_locked(host)
            if in_backoff?(entry, now)
              backed_off << { host: host, entry: entry, idx: idx }
            else
              available << { host: host, entry: entry, idx: idx, score: compute_score(entry, now) }
            end
          end

          sorted_available  = available.sort_by { |h| [h[:score], -h[:entry][:total_successes], h[:idx]] }
          sorted_backed_off = backed_off.sort_by { |h| h[:entry][:backoff_until].to_f }

          (sorted_available + sorted_backed_off).map { |h| h[:host] }
        end
      end

      # Returns a frozen copy of the internal entry hash for +host+, or +nil+
      # if the host is unknown and not in the store.
      #
      # @param host [String]
      # @return [Hash, nil]
      def snapshot(host)
        @mutex.synchronize do
          entry = @entries[host] || load_from_store(host)
          entry&.dup&.freeze
        end
      end

      # Clears all in-memory reputation data.
      def reset
        @mutex.synchronize { @entries.clear }
      end

      private

      # Returns the entry for +host+, creating a default one if absent.
      # Must be called within +@mutex.synchronize+.
      def fetch_or_create(host)
        @entries[host] ||= load_from_store(host) || default_entry(host)
      end

      # Alias used inside rank_hosts where the mutex is already held.
      alias fetch_or_create_locked fetch_or_create

      # Builds a default entry for a host with no recorded history.
      def default_entry(host)
        {
          host: host,
          total_successes: 0,
          total_failures: 0,
          consecutive_failures: 0,
          avg_latency_ms: DEFAULT_LATENCY_MS.to_f,
          last_latency_ms: nil,
          backoff_until: nil,
          last_updated_at: nil,
          last_error: nil
        }
      end

      # Returns +true+ if +latency+ is a valid, finite non-negative number.
      def valid_latency?(latency)
        return false unless latency.is_a?(Numeric)
        return false if latency.respond_to?(:nan?) && latency.nan?
        return false if latency.respond_to?(:infinite?) && latency.infinite?

        latency >= 0
      end

      # Returns +true+ if +reason+ represents a DNS-level connectivity error.
      def dns_error?(reason)
        return true if reason.is_a?(SocketError)
        return true if reason.is_a?(Errno::ECONNREFUSED)
        return false unless reason

        msg = reason.is_a?(Exception) ? reason.message : reason.to_s
        msg.include?('getaddrinfo') || msg.include?('Failed to fetch')
      end

      # Returns +true+ if the entry's backoff window is still active.
      def in_backoff?(entry, now)
        bu = entry[:backoff_until]
        bu && bu > now
      end

      # Computes the priority score for a host entry.
      #
      # Lower scores are better. The score penalises slow and unreliable
      # hosts and rewards those with many successes.
      def compute_score(entry, now)
        avg    = entry[:avg_latency_ms]
        cons   = entry[:consecutive_failures]
        succs  = entry[:total_successes]

        backoff_penalty = in_backoff?(entry, now) ? (entry[:backoff_until] - now) * 1000 : 0
        bonus           = [succs * SUCCESS_BONUS_MS, avg / 2.0].min

        avg + (cons * FAILURE_PENALTY_MS) + backoff_penalty - bonus
      end

      # Returns deduplicated list preserving the first occurrence of each host.
      def deduplicate(hosts)
        seen = {}
        hosts.each_with_object([]) do |host, acc|
          next if seen.key?(host)

          seen[host] = true
          acc << host
        end
      end

      # Loads an entry from the store adapter. Returns +nil+ if no store is
      # configured or the key is absent.
      def load_from_store(host)
        return nil unless @store

        @store.get(host)
      end

      # Persists an entry via the store adapter (no-op if no store configured).
      def persist(host, entry)
        @store&.set(host, entry)
      end
    end
  end
end
