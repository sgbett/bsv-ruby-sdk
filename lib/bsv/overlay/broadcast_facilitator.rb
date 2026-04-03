# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module BSV
  module Overlay
    # Abstract base class defining the interface for broadcast facilitators.
    #
    # A facilitator is responsible for sending a TaggedBEEF to a given
    # Overlay Services host URL and returning a parsed STEAK response.
    # Concrete subclasses implement the transport mechanism (e.g. HTTPS).
    #
    # Implementors must override +#send_beef+.
    class BroadcastFacilitator
      # Send a tagged BEEF to the given overlay host.
      #
      # @param url         [String]     base URL of the Overlay Services host
      # @param tagged_beef [TaggedBEEF] the tagged BEEF to send
      # @return [Hash{String => AdmittanceInstructions}, nil] STEAK response, or nil on failure
      # @raise [NotImplementedError] always — subclasses must implement this
      def send_beef(url, tagged_beef)
        raise NotImplementedError, "#{self.class}#send_beef must be implemented"
      end
    end

    # Default HTTPS-based broadcast facilitator using Net::HTTP.
    #
    # POSTs to +{url}/submit+ with a binary BEEF body,
    # +Content-Type: application/octet-stream+, and an +X-Topics+ header
    # containing the JSON-encoded list of topics for the tagged BEEF.
    #
    # HTTPS is enforced by default; pass +allow_http: true+ to permit plain
    # HTTP (useful for local development and testing).
    #
    # An injectable +http_client+ may be supplied for testing. It must respond
    # to +#request(uri, net_http_request)+ and return an object with +#code+
    # and +#body+.
    class HTTPSBroadcastFacilitator < BroadcastFacilitator
      # @param allow_http  [Boolean]        permit non-HTTPS URLs (default: false)
      # @param http_client [#request, nil]  injectable HTTP client for testing
      def initialize(allow_http: false, http_client: nil)
        super()
        @allow_http  = allow_http
        @http_client = http_client
      end

      # Send a tagged BEEF to +{url}/submit+ and return the parsed STEAK hash.
      #
      # @param url         [String]     base URL of the Overlay Services host
      # @param tagged_beef [TaggedBEEF] the tagged BEEF to broadcast
      # @return [Hash{String => AdmittanceInstructions}, nil]
      #   parsed STEAK response, or nil if the host returned an error or
      #   the response could not be parsed
      # @raise [ArgumentError] if the URL is not HTTPS and +allow_http+ is false
      def send_beef(url, tagged_beef)
        validate_url!(url)

        uri     = URI("#{url.chomp('/')}/submit")
        request = build_request(uri, tagged_beef)
        response = execute(uri, request)

        parse_steak(response)
      end

      private

      def validate_url!(url)
        return if @allow_http
        return if url.start_with?('https:')

        raise ArgumentError,
              'HTTPS facilitator can only use URLs that start with "https:" ' \
              '(pass allow_http: true to permit plain HTTP)'
      end

      def build_request(uri, tagged_beef)
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/octet-stream'
        request['X-Topics']     = JSON.generate(tagged_beef.topics)
        request.body            = tagged_beef.beef
        request
      end

      def execute(uri, request)
        if @http_client
          @http_client.request(uri, request)
        else
          Net::HTTP.start(
            uri.hostname,
            uri.port,
            use_ssl: uri.scheme == 'https'
          ) do |http|
            http.request(request)
          end
        end
      end

      # Parse the STEAK response body into a hash of topic => AdmittanceInstructions.
      #
      # Returns nil for non-2xx responses or unparseable bodies.
      def parse_steak(response)
        code = response.code.to_i
        return nil unless (200..299).cover?(code)

        body = parse_json(response.body)
        return nil unless body.is_a?(Hash)

        body.each_with_object({}) do |(topic, raw), steak|
          next unless raw.is_a?(Hash)

          steak[topic] = AdmittanceInstructions.new(
            outputs_to_admit: Array(raw['outputsToAdmit']),
            coins_to_retain: Array(raw['coinsToRetain']),
            coins_removed: raw['coinsRemoved'] ? Array(raw['coinsRemoved']) : nil
          )
        end
      end

      def parse_json(raw)
        JSON.parse(raw)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
