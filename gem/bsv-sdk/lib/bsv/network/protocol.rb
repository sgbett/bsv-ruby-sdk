# frozen_string_literal: true

require 'set'

module BSV
  module Network
    # Protocol is the base class for all BSV network protocol definitions.
    #
    # Subclasses declare their commands via the +endpoint+ DSL macro. Each
    # endpoint maps a command name (Symbol) to an HTTP method, a path template,
    # and a response handler. The +subscription+ macro is a placeholder for future
    # WebSocket support.
    #
    # Subclass isolation is enforced via an +inherited+ hook — each subclass
    # receives its own empty +@endpoints+ and +@subscriptions+ hashes. Adding
    # endpoints to a subclass never affects the parent.
    #
    # HTTP dispatch is not yet implemented (Task 3). Calling +call+ raises
    # +NotImplementedError+.
    #
    # == Example
    #
    #   class MyProtocol < BSV::Network::Protocol
    #     endpoint :get_tx, :get, '/v1/tx/{txid}'
    #     endpoint :broadcast, :post, '/v1/tx', response: :json
    #   end
    #
    #   p = MyProtocol.new(base_url: 'https://api.example.com', network: 'main')
    #   p.commands #=> #<Set: {:get_tx, :broadcast}>
    class Protocol
      class << self
        # Registers an endpoint definition for this protocol class.
        #
        # @param command_name [Symbol] the command name (e.g. +:broadcast+)
        # @param http_method  [Symbol] +:get+ or +:post+
        # @param path_template [String] path with +{param}+ placeholders
        # @param response [Symbol, #call] response handler — +:raw+, +:json+,
        #   +:json_array+, or a callable (lambda/proc)
        def endpoint(command_name, http_method, path_template, response: :raw)
          @endpoints[command_name] = {
            method: http_method,
            path: path_template,
            response: response
          }
        end

        # Registers a subscription definition. Placeholder for Phase C WebSocket
        # support. Stored but not callable at runtime.
        #
        # @param event_name [Symbol] the event name
        # @param path       [String] WebSocket path
        # @param opts       [Hash]   additional options (reserved)
        def subscription(event_name, path, **opts)
          @subscriptions[event_name] = { path: path }.merge(opts)
        end

        # Returns a +Set+ of command names declared on this protocol class.
        #
        # @return [Set<Symbol>]
        def commands
          Set.new(@endpoints.keys)
        end

        # Returns a frozen copy of the endpoints hash for introspection.
        #
        # @return [Hash]
        def endpoints
          @endpoints.dup.freeze
        end

        # Returns a frozen copy of the subscriptions hash for introspection.
        #
        # @return [Hash]
        def subscriptions
          @subscriptions.dup.freeze
        end

        # Give each subclass its own isolated +@endpoints+ and +@subscriptions+
        # hashes. Deep-copies the parent's endpoints so that existing declarations
        # are inherited but mutations on the subclass do not affect the parent.
        def inherited(subclass)
          super
          # Deep copy: each endpoint value is a plain hash of scalar values,
          # so a one-level transform_values dup is sufficient.
          parent_endpoints = @endpoints.each_with_object({}) do |(k, v), h|
            h[k] = v.dup
          end
          subclass.instance_variable_set(:@endpoints,     parent_endpoints)
          subclass.instance_variable_set(:@subscriptions, {})
        end
      end

      # Initialise the class-level hashes on Protocol itself so that the
      # inherited hook works correctly for direct subclasses.
      @endpoints     = {}
      @subscriptions = {}

      attr_reader :base_url, :api_key, :network, :http_client

      # @param base_url    [String] base URL, may contain +{network}+ placeholder
      # @param api_key     [String, nil] API key for authenticated requests
      # @param network     [String, Symbol, nil] network name (e.g. 'main', 'test')
      # @param http_client [Object, nil] injectable HTTP client (used in Task 3)
      def initialize(base_url:, api_key: nil, network: nil, http_client: nil)
        @api_key     = api_key
        @network     = network
        @http_client = http_client
        @base_url    = build_base_url(base_url, network)
      end

      # Dispatches a command. HTTP dispatch is not yet implemented (Task 3).
      #
      # @raise [NotImplementedError]
      def call(_command_name, *_args, **_kwargs)
        raise NotImplementedError, 'HTTP dispatch not yet implemented (Task 3)'
      end

      private

      # Resolves the final base URL by interpolating +{network}+ and stripping
      # any trailing slash.
      #
      # @param url     [String]
      # @param network [String, Symbol, nil]
      # @return [String]
      # @raise [ArgumentError] when +{network}+ placeholder is present but
      #   +network+ was not provided
      def build_base_url(url, network)
        if url.include?('{network}')
          raise ArgumentError, 'base_url contains {network} placeholder but no network: was provided' if network.nil?

          url = url.gsub('{network}', network.to_s)
        end

        url.chomp('/')
      end
    end
  end
end
