# frozen_string_literal: true

require 'set'
require 'net/http'
require 'json'
require 'uri'

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
    # HTTP dispatch routes through +call+: if a +call_<name>+ escape hatch
    # method exists on the instance, it is called; otherwise +default_call+
    # interpolates the URL template, makes the HTTP request, and maps the
    # response to a +Result+.
    #
    # == Example
    #
    #   class MyProtocol < BSV::Network::Protocol
    #     endpoint :get_tx, :get, '/v1/tx/{txid}'
    #     endpoint :broadcast, :post, '/v1/tx', response: :json
    #   end
    #
    #   p = MyProtocol.new(base_url: 'https://api.example.com', network: 'main')
    #   MyProtocol.commands #=> #<Set: {:get_tx, :broadcast}>
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

      # Dispatches a command by name.
      #
      # If a method named +call_<command_name>+ exists on the instance it is
      # used as an escape hatch — that method receives +args+ and +kwargs+
      # and MUST return a +Result+. Otherwise +default_call+ is invoked.
      #
      # Subscriptions are not callable; calling one raises +NotImplementedError+.
      #
      # @param command_name [Symbol, String] command to invoke
      # @param args   [Array]  positional arguments forwarded to path interpolation
      # @param kwargs [Hash]   keyword arguments forwarded to path interpolation
      # @return [Result::Success, Result::Error, Result::NotFound]
      # @raise [ArgumentError] when command_name is not registered
      def call(command_name, *args, **kwargs)
        name = command_name.to_sym

        if self.class.subscriptions.key?(name)
          raise NotImplementedError,
                "#{name} is a subscription — WebSocket dispatch is not yet implemented"
        end

        escape = :"call_#{name}"
        return send(escape, *args, **kwargs) if respond_to?(escape, true)

        default_call(name, *args, **kwargs)
      end

      # Dispatches a command directly via HTTP, bypassing any escape hatch.
      #
      # Path placeholders (+{param}+) are filled from +kwargs+ first; any
      # remaining placeholders are filled positionally from +args+. Named
      # kwargs take precedence over positional args for the same placeholder.
      #
      # POST body is taken from +kwargs.delete(:body)+ (removed before path
      # interpolation).
      #
      # @param command_name [Symbol] registered command name
      # @param args   [Array]  positional path parameters
      # @param kwargs [Hash]   named path parameters (and optional +:body+)
      # @return [Result::Success, Result::Error, Result::NotFound]
      # @raise [ArgumentError] when command_name is not registered or a
      #   required path parameter is missing
      def default_call(command_name, *args, **kwargs)
        name = command_name.to_sym
        defn = self.class.endpoints[name]
        raise ArgumentError, "unknown command: #{name}" unless defn

        body       = kwargs.delete(:body)
        path       = interpolate_path(defn[:path], args, kwargs)
        uri        = URI("#{@base_url}#{path}")
        request    = build_request(defn[:method], uri, body)
        response   = execute(uri, request)

        map_response(response, defn[:response])
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

      # Interpolates +{placeholder}+ tokens in a path template.
      #
      # Named kwargs are matched first (removing matched keys from the hash).
      # Remaining positional args fill placeholders in template order.
      #
      # @param template [String]  path template with +{name}+ tokens
      # @param args     [Array]   positional substitution values
      # @param kwargs   [Hash]    named substitution values (modified in place)
      # @return [String]
      # @raise [ArgumentError] when a placeholder cannot be filled
      def interpolate_path(template, args, kwargs)
        pos_args  = args.dup
        remaining = kwargs.dup

        # Extract ordered placeholder names from the template
        names = template.scan(/\{(\w+)\}/).flatten.map(&:to_sym)

        result = template.dup
        names.each do |name|
          value =
            if remaining.key?(name)
              remaining.delete(name)
            elsif !pos_args.empty?
              pos_args.shift
            else
              raise ArgumentError, "missing path parameter: #{name}"
            end
          result = result.sub("{#{name}}") { value.to_s }
        end
        result
      end

      # Builds a Net::HTTP request for the given method, URI, and optional body.
      #
      # @param http_method [Symbol] +:get+ or +:post+
      # @param uri   [URI]
      # @param body  [String, nil] raw body for POST requests
      # @return [Net::HTTPRequest]
      def build_request(http_method, uri, body)
        request =
          case http_method
          when :get  then Net::HTTP::Get.new(uri)
          when :post then Net::HTTP::Post.new(uri)
          else raise ArgumentError, "unsupported HTTP method: #{http_method}"
          end

        request['Authorization'] = "Bearer #{@api_key}" if @api_key
        if body && request.respond_to?(:body=)
          request.body = body
          request.content_type = 'application/json' unless request.content_type
        end
        request
      end

      # Executes the request via the injectable client or +Net::HTTP.start+.
      #
      # @param uri     [URI]
      # @param request [Net::HTTPRequest]
      # @return [Net::HTTPResponse]
      def execute(uri, request)
        if @http_client
          @http_client.request(uri, request)
        else
          Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
            http.request(request)
          end
        end
      end

      # Maps an HTTP response to a Result type, applying the response handler
      # on 2xx bodies.
      #
      # @param response [Net::HTTPResponse]
      # @param handler  [Symbol, #call]
      # @return [Result::Success, Result::Error, Result::NotFound]
      def map_response(response, handler)
        code = response.code.to_i

        case code
        when 200..299
          data = apply_handler(response.body, handler)
          return data if data.is_a?(Result::Error)

          Result::Success.new(data: data)
        when 404
          Result::NotFound.new
        when 429, 500..599
          Result::Error.new(message: response.body, retryable: true)
        else
          Result::Error.new(message: response.body, retryable: false)
        end
      end

      # Applies the response handler to a raw body string.
      #
      # @param body    [String, nil]
      # @param handler [Symbol, #call]
      # @return [Object, Result::Error]
      def apply_handler(body, handler)
        return body if body.nil?

        case handler
        when :raw
          body
        when :json
          JSON.parse(body)
        when :json_array
          parsed = JSON.parse(body)
          raise TypeError, "expected Array, got #{parsed.class}" unless parsed.is_a?(Array)

          parsed
        else
          raise ArgumentError, "unsupported response handler: #{handler.inspect}" unless handler.respond_to?(:call)

          handler.call(body)
        end
      rescue JSON::ParserError, TypeError => e
        Result::Error.new(message: "JSON/response error: #{e.message}", retryable: false)
      end
    end
  end
end
