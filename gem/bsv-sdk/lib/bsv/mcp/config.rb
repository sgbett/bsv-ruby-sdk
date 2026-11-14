# frozen_string_literal: true

require 'uri'

module BSV
  module MCP
    # Configuration parsed from environment variables for the MCP server.
    #
    # Environment variables (blank values count as unset):
    #   BSV_NETWORK     -- 'mainnet' or 'testnet', or the aliases 'main' and
    #                      'test' (default: 'mainnet'). Anything else raises
    #                      ArgumentError so the server fails to start rather
    #                      than guessing a network.
    #   BSV_ARC_URL     -- optional ARC endpoint for broadcasts on the server's
    #                      own network (https, or http for a loopback host; no
    #                      credentials, query or fragment)
    #   BSV_ARC_API_KEY -- optional bearer token, sent only to BSV_ARC_URL.
    #                      Ignored (with a warning) when BSV_ARC_URL is unset.
    #
    # Error messages name the variable but never echo its value.
    class Config
      MAINNET = 'mainnet'
      TESTNET = 'testnet'
      VALID_NETWORKS = [MAINNET, TESTNET].freeze

      # Chain names used by the wallet-toolboxes, accepted as shorthand.
      NETWORK_ALIASES = { 'main' => MAINNET, 'test' => TESTNET }.freeze

      # Hosts for which plain http is allowed, as they never leave the machine.
      LOOPBACK_HOSTS = %w[localhost 127.0.0.1 ::1].freeze

      attr_reader :network, :arc_url, :arc_api_key

      # @raise [ArgumentError] for an unrecognised network or an unusable ARC URL
      def initialize(network: nil, arc_url: nil, arc_api_key: nil)
        @network = parse_network(presence(network) || presence(ENV.fetch('BSV_NETWORK', nil)))
        @arc_url = parse_arc_url(presence(arc_url) || presence(ENV.fetch('BSV_ARC_URL', nil)))
        @arc_api_key = presence(arc_api_key) || presence(ENV.fetch('BSV_ARC_API_KEY', nil))
        warn_when_key_has_no_url
      end

      # Keeps the ARC key out of logs and error reports.
      def inspect
        "#<#{self.class.name} network=#{@network.inspect}>"
      end

      def mainnet?
        @network == MAINNET
      end

      def testnet?
        @network == TESTNET
      end

      private

      def presence(value)
        stripped = value.to_s.strip
        stripped unless stripped.empty?
      end

      def parse_network(value)
        return MAINNET if value.nil?

        normalised = value.downcase
        return normalised if VALID_NETWORKS.include?(normalised)
        return NETWORK_ALIASES.fetch(normalised) if NETWORK_ALIASES.key?(normalised)

        raise ArgumentError, "BSV_NETWORK must be one of: #{(VALID_NETWORKS + NETWORK_ALIASES.keys).join(', ')}"
      end

      def parse_arc_url(value)
        return if value.nil?

        uri = URI.parse(value)
        raise ArgumentError, arc_url_error unless usable_arc_uri?(uri)

        value
      rescue URI::InvalidURIError
        raise ArgumentError, arc_url_error
      end

      def usable_arc_uri?(uri)
        # ARC appends its path to the raw string, so a query or fragment would corrupt it.
        return false if uri.host.to_s.empty? || uri.userinfo || uri.query || uri.fragment

        case uri.scheme&.downcase
        when 'https' then true
        when 'http' then LOOPBACK_HOSTS.include?(uri.hostname.downcase)
        else false
        end
      end

      def arc_url_error
        'BSV_ARC_URL must be an https URL with a host, no credentials, query or fragment ' \
          '(http is accepted only for localhost, 127.0.0.1 and ::1)'
      end

      # The key is only ever sent to BSV_ARC_URL, so without one it has nowhere
      # to go. Say so rather than silently dropping it.
      def warn_when_key_has_no_url
        return unless @arc_api_key && @arc_url.nil?

        warn 'BSV::MCP::Config: BSV_ARC_API_KEY is set without BSV_ARC_URL and will be ignored'
      end
    end
  end
end
