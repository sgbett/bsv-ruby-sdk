# frozen_string_literal: true

require 'json'
require 'uri'

module BSV
  module Overlay
    # Broadcasts transactions to overlay topics via SHIP (Service Host Interconnect Protocol).
    #
    # Discovers interested overlay hosts by querying the +ls_ship+ SLAP service,
    # then dispatches a TaggedBEEF to each host in parallel and verifies
    # acknowledgements according to the configured requirements.
    #
    # == Topic validation
    #
    # All topics must be non-empty strings beginning with +tm_+. An empty
    # topics array or a topic without the +tm_+ prefix raises ArgumentError.
    #
    # == Acknowledgement modes
    #
    # Three independent ack modes may be combined:
    #
    # - +require_ack_from_any_host+ (default: +'all'+) — at least one successful
    #   host must satisfy the requirement.
    # - +require_ack_from_all_hosts+ (default: +[]+) — every successful host must
    #   satisfy the requirement. An empty array disables this check.
    # - +require_ack_from_specific_hosts+ (default: +{}+) — named hosts must
    #   each satisfy their individual requirement.
    #
    # Requirement values:
    # - +'all'+ — the host must have acknowledged every one of the broadcaster's topics.
    # - +'any'+ — the host must have acknowledged at least one topic.
    # - +Array<String>+ — the host must have acknowledged all topics in the array.
    #
    # == Host caching
    #
    # SHIP host discovery results are cached for +SHIP_CACHE_TTL+ seconds (5 minutes)
    # to avoid redundant SLAP queries on repeated broadcasts.
    class TopicBroadcaster
      # Seconds before the SHIP host cache expires.
      SHIP_CACHE_TTL = 300

      # @param topics             [Array<String>]   overlay topic names (must start with +tm_+)
      # @param network_preset     [Symbol]          +:mainnet+, +:testnet+, or +:local+
      # @param facilitator        [BroadcastFacilitator, nil] injectable facilitator
      # @param resolver           [LookupResolver, nil]       injectable resolver
      # @param require_ack_from_all_hosts    [Array, String] requirement all hosts must satisfy
      # @param require_ack_from_any_host     [String]        requirement at least one host must satisfy
      # @param require_ack_from_specific_hosts [Hash]        per-host requirements
      def initialize(
        topics,
        network_preset: :mainnet,
        facilitator: nil,
        resolver: nil,
        require_ack_from_all_hosts: [],
        require_ack_from_any_host: 'all',
        require_ack_from_specific_hosts: {}
      )
        validate_topics!(topics)

        @topics          = topics.dup.freeze
        @network_preset  = network_preset
        @facilitator     = facilitator || default_facilitator
        @resolver        = resolver    || default_resolver

        @require_ack_from_all_hosts      = require_ack_from_all_hosts
        @require_ack_from_any_host       = require_ack_from_any_host
        @require_ack_from_specific_hosts = require_ack_from_specific_hosts

        @ship_cache       = nil
        @ship_cache_at    = nil
        @ship_cache_mutex = Mutex.new
      end

      # Broadcast a transaction to all interested overlay hosts.
      #
      # @param tx [Transaction::Tx] the transaction to broadcast
      # @return [OverlayBroadcastResult]
      def broadcast(tx)
        beef = serialise_beef(tx)
        return beef if beef.is_a?(OverlayBroadcastResult)

        if local?
          host_topics = { 'http://localhost:8080' => Set.new(@topics) }
        else
          host_topics = find_interested_hosts
          if host_topics.empty?
            return error_result(
              'ERR_NO_HOSTS_INTERESTED',
              "No #{@network_preset} hosts are interested in receiving this transaction."
            )
          end
        end

        results = dispatch(beef, host_topics)

        successful = results.compact
        if successful.empty?
          return error_result(
            'ERR_ALL_HOSTS_REJECTED',
            "All #{@network_preset} topical hosts have rejected the transaction."
          )
        end

        host_acks = build_host_acks(successful)

        ack_check = check_ack_requirements(host_acks)
        return ack_check if ack_check.is_a?(OverlayBroadcastResult)

        OverlayBroadcastResult.new(
          status: 'success',
          txid: tx.txid_hex, # Overlay API boundary: display-order hex txid for the broadcast result
          message: "Sent to #{successful.size} Overlay Service host(s)."
        )
      end

      # Discover overlay hosts interested in the broadcaster's topics via SHIP.
      #
      # Results are cached for +SHIP_CACHE_TTL+ seconds.
      #
      # @return [Hash{String => Set<String>}] map of host URL to set of interested topics
      def find_interested_hosts
        @ship_cache_mutex.synchronize do
          return @ship_cache.transform_values(&:dup) if @ship_cache && (Time.now.to_f - @ship_cache_at) < SHIP_CACHE_TTL

          hosts = fetch_ship_hosts
          @ship_cache    = hosts
          @ship_cache_at = Time.now.to_f
          hosts.transform_values(&:dup)
        end
      end

      private

      # ---- Topic validation ----

      def validate_topics!(topics)
        raise ArgumentError, 'topics must be a non-empty array' if topics.nil? || topics.empty?

        topics.each do |topic|
          raise ArgumentError, "topic #{topic.inspect} must start with 'tm_'" unless topic.is_a?(String) && topic.start_with?('tm_')
        end
      end

      # ---- BEEF serialisation ----

      def serialise_beef(tx)
        tx.to_beef
      rescue StandardError => e
        error_result('ERR_BEEF_SERIALIZATION_FAILED', "Failed to serialise transaction to BEEF: #{e.message}")
      end

      # ---- SHIP host discovery ----

      def fetch_ship_hosts
        question = LookupQuestion.new(
          service: 'ls_ship',
          query: { 'topics' => @topics }
        )

        answer = @resolver.query(question)
        return {} unless answer.type == 'output-list'

        parse_ship_answer(answer)
      rescue StandardError
        {}
      end

      def parse_ship_answer(answer)
        results = {}

        answer.outputs.each do |output|
          beef_data    = output['beef'] || output[:beef]
          output_index = (output['outputIndex'] || output[:output_index] || 0).to_i
          next if output_index.negative?

          next unless beef_data

          advert = decode_ship_advert(beef_data, output_index)
          next unless advert
          next unless advert.protocol == Constants::PROTOCOL_SHIP
          next unless @topics.include?(advert.topic_or_service)

          domain = normalise_domain(advert.domain)
          next if domain.nil? || domain.empty?

          results[domain] ||= Set.new
          results[domain] << advert.topic_or_service
        rescue StandardError
          next
        end

        results
      end

      def decode_ship_advert(beef_data, output_index)
        beef = parse_beef(beef_data)
        return nil unless beef

        beef_tx = beef.transactions.last
        return nil if beef_tx.nil? || beef_tx.is_a?(BSV::Transaction::Beef::TxidOnlyEntry)

        tx    = beef_tx.transaction
        txout = tx.outputs[output_index]
        return nil unless txout

        AdminTokenTemplate.decode(txout.locking_script)
      rescue StandardError
        nil
      end

      def parse_beef(beef_data)
        case beef_data
        when String
          BSV::Transaction::Beef.from_binary(beef_data)
        when Array
          BSV::Transaction::Beef.from_binary(beef_data.pack('C*'))
        end
      rescue StandardError
        nil
      end

      def normalise_domain(domain)
        url = domain.start_with?('https://', 'http://') ? domain : "https://#{domain}"
        return nil if private_url?(url)

        url
      end

      # Reject URLs whose hostname is a private/loopback IP literal (SSRF protection).
      def private_url?(url)
        require 'ipaddr'
        host = URI(url).hostname
        return true if host.nil? || host.empty?

        addr = IPAddr.new(host)
        addr.loopback? || addr.private? || addr.link_local?
      rescue IPAddr::InvalidAddressError
        false # Not an IP literal — domain names pass through
      end

      # ---- Parallel dispatch ----

      def dispatch(beef, host_topics)
        results   = {}
        mutex     = Mutex.new

        threads = host_topics.map do |host, host_topic_set|
          Thread.new do
            topics_for_host = @topics.select { |t| host_topic_set.include?(t) }
            tagged = TaggedBEEF.new(beef: beef, topics: topics_for_host)
            steak  = @facilitator.send_beef(host, tagged)
            mutex.synchronize { results[host] = steak }
          rescue StandardError
            mutex.synchronize { results[host] = nil }
          end
        end

        threads.each(&:join)
        results
      end

      # ---- Acknowledgement tracking ----

      # Build a map of host → Set of acknowledged topic names.
      #
      # A topic is considered acknowledged if the host's AdmittanceInstructions
      # for that topic has at least one entry in +outputs_to_admit+,
      # +coins_to_retain+, or +coins_removed+.
      def build_host_acks(successful_results)
        successful_results.each_with_object({}) do |(host, steak), acks|
          next unless steak.is_a?(Hash)

          acked = Set.new
          steak.each do |topic, instructions|
            next unless instructions.is_a?(AdmittanceInstructions)

            admit = instructions.outputs_to_admit
            retain = instructions.coins_to_retain
            removed = instructions.coins_removed

            next unless (admit && !admit.empty?) ||
                        (retain && !retain.empty?) ||
                        (removed && !removed.empty?)

            acked << topic
          end
          acks[host] = acked
        end
      end

      # Check all three ack requirement modes and return an error result if
      # any check fails, or nil on success.
      def check_ack_requirements(host_acks)
        if any_host_requirement_active? && !any_host_satisfies?(host_acks, @require_ack_from_any_host)
          return error_result(
            'ERR_REQUIRE_ACK_FROM_ANY_HOST_FAILED',
            'No host acknowledged the required topics.'
          )
        end

        if all_hosts_requirement_active? && !all_hosts_satisfy?(host_acks, @require_ack_from_all_hosts)
          return error_result(
            'ERR_REQUIRE_ACK_FROM_ALL_HOSTS_FAILED',
            'Not all hosts acknowledged the required topics.'
          )
        end

        if @require_ack_from_specific_hosts.any? && !specific_hosts_satisfy?(host_acks)
          return error_result(
            'ERR_REQUIRE_ACK_FROM_SPECIFIC_HOSTS_FAILED',
            'Specific hosts did not acknowledge the required topics.'
          )
        end

        nil
      end

      def any_host_requirement_active?
        req = @require_ack_from_any_host
        req && req != []
      end

      def all_hosts_requirement_active?
        req = @require_ack_from_all_hosts
        req && req != [] && !req.empty?
      end

      # Returns true if at least one host in +host_acks+ satisfies +requirement+.
      def any_host_satisfies?(host_acks, requirement)
        host_acks.any? { |_host, acked| host_meets_requirement?(acked, requirement) }
      end

      # Returns true if every host in +host_acks+ satisfies +requirement+.
      def all_hosts_satisfy?(host_acks, requirement)
        host_acks.all? { |_host, acked| host_meets_requirement?(acked, requirement) }
      end

      # Returns true if every named host in +require_ack_from_specific_hosts+
      # responded and met its individual requirement.
      def specific_hosts_satisfy?(host_acks)
        @require_ack_from_specific_hosts.all? do |host, requirement|
          acked = host_acks[host]
          next false unless acked

          host_meets_requirement?(acked, requirement)
        end
      end

      # Evaluate whether a host's acknowledged topic set satisfies a requirement.
      #
      # @param acked       [Set<String>] topics the host acknowledged
      # @param requirement [String, Array<String>] +'all'+, +'any'+, or topic list
      def host_meets_requirement?(acked, requirement)
        case requirement
        when 'all'
          @topics.all? { |t| acked.include?(t) }
        when 'any'
          @topics.any? { |t| acked.include?(t) }
        when Array
          requirement.all? { |t| acked.include?(t) }
        else
          true
        end
      end

      # ---- Result helpers ----

      def error_result(code, description)
        OverlayBroadcastResult.new(status: 'error', code: code, description: description)
      end

      # ---- Defaults ----

      def local?
        @network_preset == :local
      end

      def default_facilitator
        if local?
          HTTPSBroadcastFacilitator.new(allow_http: true)
        else
          HTTPSBroadcastFacilitator.new
        end
      end

      def default_resolver
        LookupResolver.new(network_preset: @network_preset)
      end
    end

    # Alias for TopicBroadcaster.
    #
    # SHIPBroadcaster and TopicBroadcaster are the same class; the alias exists
    # for compatibility with the Go and TypeScript SDKs where the class is known
    # by both names.
    SHIPBroadcaster = TopicBroadcaster
  end
end
