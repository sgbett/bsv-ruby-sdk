# frozen_string_literal: true

require 'uri'

module BSV
  module Transaction
    module FeeModels
      # Dynamic fee model that fetches the live mining fee rate from an ARC
      # policy endpoint.
      #
      # The policy is fetched through {BSV::Network::Protocols::ARC}, so it
      # inherits that layer's timeouts, transport-error handling and
      # credential-free +inspect+. The fetched rate is cached for a
      # configurable TTL (default 5 minutes) so repeated calls to
      # {#compute_fee} do not repeatedly query the API. If a fetch fails or
      # the policy is implausible, the model returns the last cached rate, or
      # failing that a configurable fallback.
      #
      # @example
      #   model = BSV::Transaction::FeeModels::LivePolicy.new(
      #     arc_url: 'https://arc.gorillapool.io',
      #     fallback_rate: 50
      #   )
      #   fee = model.compute_fee(transaction)
      class LivePolicy < FeeModel
        DEFAULT_CACHE_TTL = 300 # 5 minutes in seconds

        # @return [String] the ARC base URL
        attr_reader :arc_url

        # @return [Integer] fallback sat/kB when fetch fails
        attr_reader :fallback_rate

        # @return [Integer] cache TTL in seconds
        attr_reader :cache_ttl

        DEFAULT_FALLBACK_RATE = 100

        # GorillaPool's public ARC instance, which serves /v1/policy without
        # credentials. Matches the TypeScript SDK's +LivePolicy+.
        GORILLAPOOL_ARC_URL = 'https://arc.gorillapool.io'

        # Sanity bounds for a fetched policy, so a hostile or broken endpoint
        # cannot dictate an absurd fee.
        # Attribution: ts-stack packages/sdk/src/transaction/fee-models/LivePolicy.ts
        MAX_POLICY_SATOSHIS = 2_100_000_000_000_000 # 21e14
        MAX_POLICY_BYTES = 1_000_000_000
        MAX_RATE_SAT_PER_KB = 1_000_000_000

        # Alternative policy keys that carry a sat/kB rate directly.
        DIRECT_RATE_KEYS = %w[satPerKb sat_per_kb satoshisPerKb].freeze

        # Returns a LivePolicy using GorillaPool's ARC for fee policy, a
        # 100 sat/kB fallback, and a 5-minute cache.
        #
        # GorillaPool needs no credentials, so no key is accepted: use
        # +LivePolicy.new(arc_url:, api_key:)+ for a keyed policy endpoint.
        #
        # @return [LivePolicy]
        def self.default
          new(arc_url: GORILLAPOOL_ARC_URL, fallback_rate: DEFAULT_FALLBACK_RATE)
        end

        # @param arc_url [String] ARC base URL (e.g. 'https://arc.gorillapool.io')
        # @param fallback_rate [Integer] sat/kB to use when fetch fails (default: 100)
        # @param cache_ttl [Integer] seconds to cache a fetched rate (default: 300)
        # @param api_key [String, nil] optional Bearer token for ARC authentication
        # @param http_client [#request, nil] injectable HTTP client for testing
        def initialize(arc_url:, fallback_rate: DEFAULT_FALLBACK_RATE, cache_ttl: DEFAULT_CACHE_TTL, api_key: nil, http_client: nil)
          super()
          @arc_url = arc_url.chomp('/')
          @fallback_rate = fallback_rate
          @cache_ttl = cache_ttl
          @protocol = BSV::Network::Protocols::ARC.new(base_url: @arc_url, api_key: api_key, http_client: http_client)
          @cached_rate = nil
          @cached_at = nil
          @mutex = Mutex.new
        end

        # Compute the fee for a transaction using the latest ARC rate.
        #
        # @param transaction [Transaction::Tx] the transaction to compute the fee for
        # @return [Integer] the fee in satoshis
        def compute_fee(transaction)
          rate = current_rate
          size = transaction.estimated_size
          (size / 1000.0 * rate).ceil
        end

        # Return the current sat/kB rate, fetching from ARC if the cache
        # has expired.
        #
        # @return [Integer] satoshis per kilobyte
        def current_rate
          @mutex.synchronize do
            return @cached_rate if cache_valid?

            rate = fetch_rate
            if rate
              @cached_rate = rate
              @cached_at = Time.now
              rate
            elsif @cached_rate
              @cached_rate
            else
              @fallback_rate
            end
          end
        end

        # Built from an allow-list so the ARC credential can never leak
        # through logs or +pp+.
        #
        # @return [String]
        def inspect
          uri = parsed_arc_uri
          "#<#{self.class.name} scheme=#{uri&.scheme.inspect} host=#{uri&.host.inspect} " \
            "fallback_rate=#{@fallback_rate} cache_ttl=#{@cache_ttl}>"
        end
        alias to_s inspect

        private

        def parsed_arc_uri
          URI.parse(@arc_url)
        rescue URI::InvalidURIError
          nil
        end

        def cache_valid?
          @cached_rate && @cached_at && (Time.now - @cached_at) < @cache_ttl
        end

        def fetch_rate
          response = @protocol.call(:get_policy)
          return unless response.http_success?

          payload = response.data
          # Some endpoints wrap the policy in a 'data' key
          payload = payload['data'] if payload.is_a?(Hash) && payload['data'].is_a?(Hash)

          extract_rate(payload)
        rescue StandardError
          nil
        end

        def extract_rate(payload)
          policy = payload.is_a?(Hash) ? payload['policy'] : nil
          return unless policy.is_a?(Hash)

          mining_fee_rate(policy) || direct_rate(policy)
        end

        # GorillaPool serves policy.miningFee; policy.fees.miningFee is the
        # shape some other ARC deployments use.
        def mining_fee_rate(policy)
          fees = policy['fees']
          mining_fee = fees.is_a?(Hash) ? fees['miningFee'] : nil
          mining_fee ||= policy['miningFee']
          return unless mining_fee.is_a?(Hash)

          satoshis = mining_fee['satoshis']
          bytes = mining_fee['bytes']
          return unless integer_within?(satoshis, MAX_POLICY_SATOSHIS) && integer_within?(bytes, MAX_POLICY_BYTES)

          normalise_rate(satoshis * 1000.0 / bytes)
        end

        def direct_rate(policy)
          DIRECT_RATE_KEYS.each do |key|
            rate = normalise_rate(policy[key])
            return rate if rate
          end

          nil
        end

        def integer_within?(value, max)
          value.is_a?(Integer) && value.between?(1, max)
        end

        # A zero rate is invalid rather than clamped to 1, as in the TypeScript SDK.
        def normalise_rate(value)
          return unless value.is_a?(Numeric) && value.finite? && value.positive? && value <= MAX_RATE_SAT_PER_KB

          [1, value.round].max
        end
      end
    end
  end
end
