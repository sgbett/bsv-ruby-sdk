# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module BSV
  module Transaction
    module FeeModels
      # Dynamic fee model that fetches the live mining fee rate from an ARC
      # policy endpoint.
      #
      # The fetched rate is cached for a configurable TTL (default 5 minutes)
      # so repeated calls to {#compute_fee} do not repeatedly query the API.
      # If a fetch fails, the model falls back to a configurable default rate.
      #
      # @example
      #   model = BSV::Transaction::FeeModels::LivePolicy.new(
      #     arc_url: 'https://arcade.gorillapool.io',
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

        DEFAULT_ARC_URL = BSV::MAINNET_URL
        DEFAULT_FALLBACK_RATE = 100

        # Returns a LivePolicy with sensible defaults (GorillaPool ARC,
        # 100 sat/kB fallback, 5-minute cache).
        #
        # @param api_key [String, nil] optional ARC API key
        # @return [LivePolicy]
        def self.default(api_key: nil)
          new(arc_url: DEFAULT_ARC_URL, fallback_rate: DEFAULT_FALLBACK_RATE, api_key: api_key)
        end

        # @param arc_url [String] ARC base URL (e.g. 'https://arcade.gorillapool.io')
        # @param fallback_rate [Integer] sat/kB to use when fetch fails (default: 100)
        # @param cache_ttl [Integer] seconds to cache a fetched rate (default: 300)
        # @param api_key [String, nil] optional Bearer token for ARC authentication
        # @param http_client [#request, nil] injectable HTTP client for testing
        def initialize(arc_url:, fallback_rate: DEFAULT_FALLBACK_RATE, cache_ttl: DEFAULT_CACHE_TTL, api_key: nil, http_client: nil)
          super()
          @arc_url = arc_url.chomp('/')
          @fallback_rate = fallback_rate
          @cache_ttl = cache_ttl
          @api_key = api_key
          @http_client = http_client
          @cached_rate = nil
          @cached_at = nil
          @mutex = Mutex.new
        end

        # Compute the fee for a transaction using the latest ARC rate.
        #
        # @param transaction [Transaction] the transaction to compute the fee for
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

        private

        def cache_valid?
          @cached_rate && @cached_at && (Time.now - @cached_at) < @cache_ttl
        end

        def fetch_rate
          uri = URI("#{@arc_url}/v1/policy")
          request = Net::HTTP::Get.new(uri)
          request['Accept'] = 'application/json'
          request['Authorization'] = "Bearer #{@api_key}" if @api_key

          response = execute(uri, request)
          return unless (200..299).cover?(response.code.to_i)

          payload = JSON.parse(response.body)
          # Some endpoints wrap the policy in a 'data' key
          payload = payload['data'] if payload.is_a?(Hash) && payload.key?('data') && payload['data'].is_a?(Hash)

          extract_rate(payload)
        rescue StandardError
          nil
        end

        def extract_rate(payload)
          policy = payload.is_a?(Hash) ? payload['policy'] : nil
          return unless policy.is_a?(Hash)

          # Primary: policy.fees.miningFee { satoshis: x, bytes: y }
          fees = policy['fees']
          mining_fee = fees.is_a?(Hash) ? fees['miningFee'] : nil
          mining_fee ||= policy['miningFee']

          if mining_fee.is_a?(Hash)
            satoshis = mining_fee['satoshis']
            bytes = mining_fee['bytes']
            return [1, (satoshis.to_f / bytes * 1000).round].max if satoshis.is_a?(Numeric) && bytes.is_a?(Numeric) && bytes.positive?
          end

          # Fallback: direct sat/kB keys
          %w[satPerKb sat_per_kb satoshisPerKb].each do |key|
            value = policy[key]
            return [1, value.round].max if value.is_a?(Numeric) && value.positive?
          end

          nil
        end

        def execute(uri, request)
          if @http_client
            @http_client.request(uri, request)
          else
            Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
              http.request(request)
            end
          end
        end
      end
    end
  end
end
