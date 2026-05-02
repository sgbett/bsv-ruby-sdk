# frozen_string_literal: true

require 'set'
require 'uri'

module BSV
  module Overlay
    # Resolves LookupQuestions by discovering competent overlay hosts via SLAP
    # trackers and querying them in parallel.
    #
    # == Host discovery
    #
    # For any service other than +ls_slap+, the resolver first queries the
    # configured SLAP trackers to discover which hosts advertise competence for
    # that service. Discovery results are cached with a configurable TTL
    # (default: 5 minutes) to avoid redundant network round-trips.
    #
    # == Host overrides and additional hosts
    #
    # +host_overrides+ replaces SLAP discovery entirely for a named service.
    # +additional_hosts+ supplements discovered (or overridden) hosts. Both
    # maps require service names that begin with +ls_+.
    #
    # == Parallel querying
    #
    # All competent hosts are queried concurrently using Ruby threads.
    # Responses are collected, outputs are merged, and duplicates are removed
    # by +"#{txid}.#{output_index}"+ key.
    #
    # == Reputation tracking
    #
    # Hosts are ranked before querying via +HostReputationTracker#rank_hosts+,
    # and success/failure outcomes (with latency) are recorded after each
    # query.
    #
    # Thread-safe via an internal Mutex on the hosts cache.
    class LookupResolver
      # Grace window (seconds) after the first valid response arrives during
      # which other in-flight host queries may still contribute their outputs.
      QUERY_GRACE_SECONDS = 0.08

      # Timeout applied when querying SLAP trackers for host discovery.
      SLAP_TRACKER_TIMEOUT = 5

      # @param network_preset     [Symbol]                 :mainnet, :testnet, or :local
      # @param facilitator        [LookupFacilitator, nil] injectable facilitator
      # @param slap_trackers      [Array<String>, nil]     override default tracker list
      # @param host_overrides     [Hash{String=>Array<String>}]
      # @param additional_hosts   [Hash{String=>Array<String>}]
      # @param reputation_tracker [HostReputationTracker, nil] injectable tracker
      # @param cache_ttl          [Integer]                seconds before cached hosts expire
      def initialize(
        network_preset:     :mainnet,
        facilitator:        nil,
        slap_trackers:      nil,
        host_overrides:     {},
        additional_hosts:   {},
        reputation_tracker: nil,
        cache_ttl:          300
      )
        @network_preset = network_preset

        @facilitator = facilitator || default_facilitator

        @slap_trackers = slap_trackers || default_slap_trackers
        validate_slap_trackers!

        validate_service_keys!('host_overrides',   host_overrides)
        validate_service_keys!('additional_hosts', additional_hosts)

        @host_overrides   = host_overrides
        @additional_hosts = additional_hosts

        @reputation_tracker = reputation_tracker || HostReputationTracker.new

        @cache_ttl   = cache_ttl
        @hosts_cache = {}
        @cache_mutex = Mutex.new
      end

      # Resolve a LookupQuestion by discovering competent hosts and querying them.
      #
      # @param question [LookupQuestion] the question to resolve
      # @param timeout  [Integer, nil]   per-host query timeout in seconds
      # @return [LookupAnswer] merged and deduplicated answer
      # @raise [NoCompetentHostsError] if no hosts can be found or all fail
      def query(question, timeout: nil)
        competent_hosts = resolve_hosts(question)
        apply_additional_hosts!(competent_hosts, question.service)

        if competent_hosts.empty?
          raise NoCompetentHostsError,
                "No competent #{@network_preset} hosts found by the SLAP trackers " \
                "for lookup service: #{question.service}"
        end

        ranked = @reputation_tracker.rank_hosts(competent_hosts)
        answers = query_hosts_in_parallel(ranked, question, timeout)

        if answers.empty?
          raise NoCompetentHostsError,
                "All competent hosts for #{question.service} failed to return a valid answer"
        end

        merge_answers(answers)
      end

      # Discover competent hosts for +service+ via SLAP trackers.
      #
      # Results are cached for +cache_ttl+ seconds. Concurrent callers for the
      # same service will each trigger their own SLAP query (no in-flight
      # coalescing in this implementation).
      #
      # @param service [String] lookup service name (e.g. +'ls_foo'+)
      # @return [Array<String>] array of host URLs
      def find_competent_hosts(service)
        cached = @cache_mutex.synchronize { @hosts_cache[service] }
        return cached[:hosts].dup if cached && (Time.now.to_f - cached[:fetched_at]) < @cache_ttl

        hosts = fetch_hosts_from_slap(service)
        @cache_mutex.synchronize do
          @hosts_cache[service] = { hosts: hosts, fetched_at: Time.now.to_f }
        end
        hosts
      end

      private

      # ---- Host resolution ----

      def resolve_hosts(question)
        service = question.service

        if service == 'ls_slap'
          return local? ? ['http://localhost:8080'] : @slap_trackers.dup
        end

        return @host_overrides[service].dup if @host_overrides.key?(service)

        return ['http://localhost:8080'] if local?

        find_competent_hosts(service)
      end

      def apply_additional_hosts!(hosts, service)
        extras = @additional_hosts[service]
        return unless extras&.any?

        seen = hosts.to_set
        extras.each { |h| hosts << h unless seen.include?(h) }
      end

      # ---- SLAP discovery ----

      def fetch_hosts_from_slap(service)
        slap_question = LookupQuestion.new(service: 'ls_slap', query: { 'service' => service })

        all_hosts = []
        threads   = @slap_trackers.map do |tracker|
          Thread.new do
            started_at = Time.now
            answer = @facilitator.lookup(tracker, slap_question, timeout: SLAP_TRACKER_TIMEOUT)
            latency_ms = ((Time.now - started_at) * 1000).round
            @reputation_tracker.record_success(tracker, latency_ms)
            extract_hosts_from_answer(answer, service)
          rescue StandardError => e
            @reputation_tracker.record_failure(tracker, e)
            []
          end
        end

        threads.each do |t|
          result = t.value
          all_hosts.concat(result) if result
        end

        all_hosts.uniq
      end

      def extract_hosts_from_answer(answer, service)
        hosts = []
        return hosts unless answer.type == 'output-list'

        answer.outputs.each do |output|
          hosts << extract_host_from_output(output, service)
        rescue StandardError
          next # Skip corrupted or invalid outputs
        end

        hosts.compact
      end

      def extract_host_from_output(output, service)
        beef_data = output['beef'] || output[:beef]
        output_index = output['outputIndex'] || output[:output_index] || 0
        output_index = output_index.to_i
        return nil if output_index.negative?

        return nil unless beef_data

        beef = parse_beef(beef_data)
        return nil unless beef

        # Get the last (subject) transaction — typically the most recent entry
        beef_tx = beef.transactions.last
        return nil unless beef_tx&.transaction

        tx     = beef_tx.transaction
        txout  = tx.outputs[output_index]
        return nil unless txout

        advert = AdminTokenTemplate.decode(txout.locking_script)
        return nil unless advert
        return nil unless advert.protocol == Constants::PROTOCOL_SLAP
        return nil unless advert.topic_or_service == service

        domain = advert.domain
        return nil if domain.nil? || domain.empty?

        url = domain.start_with?('https://', 'http://') ? domain : "https://#{domain}"
        return nil if private_url?(url)

        url
      end

      def parse_beef(beef_data)
        case beef_data
        when String
          BSV::Transaction::Beef.from_binary(beef_data)
        when Array
          # Array of integers (TS SDK wire format)
          BSV::Transaction::Beef.from_binary(beef_data.pack('C*'))
        end
      rescue StandardError
        nil
      end

      # ---- Parallel host querying ----

      def query_hosts_in_parallel(hosts, question, timeout)
        results     = []
        results_mu  = Mutex.new
        resolved    = false
        resolved_mu = Mutex.new
        pending     = hosts.length

        grace_cv    = ConditionVariable.new
        done_mu     = Mutex.new
        done        = false

        threads = hosts.map do |host|
          Thread.new do
            answer = lookup_with_tracking(host, question, timeout)
            if answer && answer.type == 'output-list'
              results_mu.synchronize { results << answer }

              resolved_mu.synchronize do
                unless resolved
                  resolved = true
                  # Signal that we can start the grace-window countdown
                  done_mu.synchronize { grace_cv.signal }
                end
              end
            end
          rescue StandardError
            nil # Failure already recorded by lookup_with_tracking
          ensure
            remaining = nil
            results_mu.synchronize do
              pending -= 1
              remaining = pending
            end
            # If all threads are done, wake any waiter
            done_mu.synchronize { grace_cv.signal } if remaining.zero?
          end
        end

        # Wait for either (a) first result + grace window, or (b) all threads done
        done_mu.synchronize do
          grace_cv.wait(done_mu) # Wait for first result or all done

          first_resolved = resolved_mu.synchronize { resolved }
          if first_resolved
            remaining_threads = threads.count(&:alive?)
            grace_cv.wait(done_mu, QUERY_GRACE_SECONDS) if remaining_threads.positive?
          end

          done = true
        end

        threads.each(&:join)

        results_mu.synchronize { results.dup }
      end

      def lookup_with_tracking(host, question, timeout)
        started_at = Time.now
        opts       = timeout ? { timeout: timeout } : {}
        answer     = @facilitator.lookup(host, question, **opts)
        latency_ms = ((Time.now - started_at) * 1000).round

        valid = answer.is_a?(LookupAnswer) &&
                answer.type == 'output-list' &&
                answer.outputs.is_a?(Array)

        if valid
          @reputation_tracker.record_success(host, latency_ms)
        else
          @reputation_tracker.record_failure(host, 'Invalid lookup response')
        end

        answer
      rescue StandardError => e
        @reputation_tracker.record_failure(host, e)
        raise
      end

      # ---- Result aggregation ----

      def merge_answers(answers)
        outputs_map = {}

        answers.each do |answer|
          answer.outputs.each do |output|
            key = dedup_key(output)
            outputs_map[key] ||= output
          end
        end

        LookupAnswer.new(type: 'output-list', outputs: outputs_map.values)
      end

      def dedup_key(output)
        beef_data    = output['beef'] || output[:beef]
        output_index = (output['outputIndex'] || output[:output_index] || 0).to_i

        # Overlay API boundary: outpoint key uses display-order hex txid
        dtxid_hex =
          begin
            beef = parse_beef(beef_data)
            last = beef&.transactions&.last
            last&.dtxid
          rescue StandardError
            nil
          end

        dtxid_hex ? "#{dtxid_hex}.#{output_index}" : output.object_id.to_s
      end

      # ---- Validation ----

      def validate_service_keys!(name, hash)
        hash.each_key do |service|
          next if service.start_with?('ls_')

          raise ArgumentError,
                "#{name} service names must start with \"ls_\": #{service}"
        end
      end

      def validate_slap_trackers!
        return if local?
        return if @slap_trackers.is_a?(Array) && !@slap_trackers.empty?

        raise ArgumentError, 'slap_trackers must be a non-empty array for non-local presets'
      end

      # ---- Helpers ----

      def local?
        @network_preset == :local
      end

      # Reject URLs whose hostname is a private/loopback IP literal (SSRF protection).
      # Only applied to SLAP-discovered domains, not to user-configured overrides.
      # Does not perform DNS resolution — only catches IP-literal hostnames like
      # 127.0.0.1, 169.254.x.x, 10.x.x.x, 192.168.x.x, etc. Domain-name SSRF
      # (DNS rebinding) is outside the scope of this check.
      def private_url?(url)
        require 'ipaddr'
        host = URI(url).hostname
        return true if host.nil? || host.empty?

        addr = IPAddr.new(host)
        addr.loopback? || addr.private? || addr.link_local?
      rescue IPAddr::InvalidAddressError
        false # Not an IP literal — allow (domain names pass through)
      end

      def default_facilitator
        if local?
          HTTPSLookupFacilitator.new(allow_http: true)
        else
          HTTPSLookupFacilitator.new
        end
      end

      def default_slap_trackers
        case @network_preset
        when :mainnet then Constants::DEFAULT_SLAP_TRACKERS.dup
        when :testnet then Constants::DEFAULT_TESTNET_SLAP_TRACKERS.dup
        else []
        end
      end
    end
  end
end
