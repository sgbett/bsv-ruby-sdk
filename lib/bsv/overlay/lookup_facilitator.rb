# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module BSV
  module Overlay
    # Abstract base class defining the interface for lookup facilitators.
    #
    # A facilitator is responsible for sending a LookupQuestion to a given
    # Overlay Services host URL and returning a LookupAnswer. Concrete
    # subclasses implement the transport mechanism (e.g. HTTPS, in-process).
    #
    # Implementors must override +#lookup+.
    class LookupFacilitator
      # Send a lookup question to the given host URL.
      #
      # @param url      [String]          base URL of the Overlay Services host
      # @param question [LookupQuestion]  the question to ask
      # @param timeout  [Integer]         seconds to wait for a response
      # @return [LookupAnswer]
      # @raise [NotImplementedError] always — subclasses must implement this
      def lookup(url, question, timeout: 5)
        raise NotImplementedError, "#{self.class}#lookup must be implemented"
      end
    end

    # Default HTTPS-based lookup facilitator using Net::HTTP.
    #
    # POSTs to +{url}/lookup+ with a JSON body and the +X-Aggregation: yes+
    # header, as required by the BSV Overlay Services protocol.
    #
    # HTTPS is enforced by default; pass +allow_http: true+ to permit plain
    # HTTP (useful for local development and testing).
    #
    # An injectable +http_client+ may be supplied for testing. It must respond
    # to +#request(uri, net_http_request)+ and return an object with +#code+
    # and +#body+.
    class HTTPSLookupFacilitator < LookupFacilitator
      # @param allow_http  [Boolean]        permit non-HTTPS URLs (default: false)
      # @param http_client [#request, nil]  injectable HTTP client for testing
      def initialize(allow_http: false, http_client: nil)
        super()
        @allow_http  = allow_http
        @http_client = http_client
      end

      # Perform an HTTPS POST to +{url}/lookup+ and return the parsed answer.
      #
      # @param url      [String]         base URL of the Overlay Services host
      # @param question [LookupQuestion] the question to send
      # @param timeout  [Integer]        request timeout in seconds (default: 5)
      # @return [LookupAnswer]
      # @raise [ArgumentError] if the URL is not HTTPS and +allow_http+ is false
      # @raise [RuntimeError]  if the server returns a non-2xx status
      def lookup(url, question, timeout: 5)
        validate_url!(url)

        uri     = URI("#{url.chomp('/')}/lookup")
        request = build_request(uri, question)

        response = execute(uri, request, timeout)
        handle_response(response)
      end

      private

      def validate_url!(url)
        return if @allow_http
        return if url.start_with?('https:')

        raise ArgumentError,
              'HTTPS facilitator can only use URLs that start with "https:" ' \
              '(pass allow_http: true to permit plain HTTP)'
      end

      def build_request(uri, question)
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request['X-Aggregation'] = 'yes'
        request.body = JSON.generate(
          'service' => question.service,
          'query' => question.query
        )
        request
      end

      def execute(uri, request, timeout)
        if @http_client
          @http_client.request(uri, request)
        else
          Net::HTTP.start(
            uri.hostname,
            uri.port,
            use_ssl: uri.scheme == 'https',
            open_timeout: timeout,
            read_timeout: timeout
          ) do |http|
            http.request(request)
          end
        end
      end

      def handle_response(response)
        code = response.code.to_i
        raise "Failed to facilitate lookup (HTTP #{code}): #{response.body}" unless (200..299).cover?(code)

        body = parse_json(response.body)
        type    = body['type'] || 'output-list'
        outputs = body['outputs'] || []
        LookupAnswer.new(type: type, outputs: outputs)
      end

      def parse_json(raw)
        JSON.parse(raw)
      rescue JSON::ParserError
        {}
      end
    end
  end
end
