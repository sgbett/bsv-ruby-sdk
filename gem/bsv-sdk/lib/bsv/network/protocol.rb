# frozen_string_literal: true

require 'net/http'
require 'json'
require 'openssl'
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
    # interpolates the URL template, makes the HTTP request, and wraps the
    # response in a +ProtocolResponse+.
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
          parent_subscriptions = @subscriptions.each_with_object({}) do |(k, v), h|
            h[k] = v.dup
          end
          subclass.instance_variable_set(:@endpoints,     parent_endpoints)
          subclass.instance_variable_set(:@subscriptions, parent_subscriptions)
        end
      end

      # Initialise the class-level hashes on Protocol itself so that the
      # inherited hook works correctly for direct subclasses.
      @endpoints     = {}
      @subscriptions = {}

      # Seconds. These bound individual socket operations, not the whole request:
      # +open_timeout+ applies separately to the TCP connect and the TLS handshake,
      # and +read_timeout+ to each socket read, so a slow but steadily trickling
      # response can outlast them.
      OPEN_TIMEOUT  = 10
      READ_TIMEOUT  = 30
      WRITE_TIMEOUT = 30

      # Failures of the transport itself, as opposed to the service or the caller.
      # +Timeout::Error+ covers the Net::*Timeout classes, +IOError+ covers
      # +EOFError+ and +SystemCallError+ covers every +Errno::*+.
      TRANSPORT_ERRORS = [
        Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError,
        Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError
      ].freeze

      # Failures that can only happen before any request bytes are sent. Every
      # other transport failure (a reset, a broken pipe, EOF, a malformed reply,
      # a mid-stream TLS error, a read or write timeout) may arrive after the
      # service has received the request, so the default is to say the outcome
      # is unknown: that matters to callers that submit data, and wrongly
      # claiming "not delivered" is the costlier mistake. EHOSTUNREACH and
      # ENETUNREACH are left out because they can surface on a connection that
      # is already open.
      NOT_SENT_ERRORS = [SocketError, Net::OpenTimeout, Errno::ECONNREFUSED].freeze

      attr_reader :base_url, :api_key, :auth, :network

      # An injected client replaces +Net::HTTP+ entirely, so it is also the way to
      # customise timeouts or other transport behaviour.
      attr_reader :http_client

      # @param base_url    [String] base URL, may contain +{network}+ placeholder
      # @param api_key     [String, nil] legacy API key — sends +Authorization: Bearer <key>+
      # @param auth        [Hash, Symbol, nil] auth config hash; takes precedence over +api_key:+.
      #   Supported forms:
      #   - +{ bearer: 'token' }+ → +Authorization: Bearer token+
      #   - +{ api_key: 'key' }+ → +Authorization: key+ (no Bearer prefix, WoC style)
      #   - +{ api_key: 'key', header: 'X-Custom' }+ → +X-Custom: key+
      #   - +:none+ or +nil+ → no auth header
      # @param network     [String, Symbol, nil] network name (e.g. 'main', 'test')
      # @param http_client [Object, nil] injectable HTTP client (used in Task 3)
      def initialize(base_url:, api_key: nil, auth: nil, network: nil, http_client: nil)
        @api_key     = api_key
        @auth        = normalise_auth(auth)
        @network     = network
        @http_client = http_client
        @base_url    = build_base_url(base_url, network)
      end

      # Dispatches a command by name.
      #
      # If a method named +call_<command_name>+ exists on the instance it is
      # used as an escape hatch — that method receives +args+ and +kwargs+
      # and MUST return a +ProtocolResponse+. Otherwise +default_call+ is invoked.
      #
      # Subscriptions are not callable; calling one raises +NotImplementedError+.
      #
      # Transport failures (see +TRANSPORT_ERRORS+) never raise: they come back as
      # a failed +ProtocolResponse+.
      #
      # @param command_name [Symbol, String] command to invoke
      # @param *      [Array]  positional arguments forwarded to path interpolation
      # @param kwargs [Hash]   keyword arguments forwarded to path interpolation
      # @return [ProtocolResponse]
      # @raise [ArgumentError] when command_name is not registered
      def call(command_name, *, **kwargs)
        name = command_name.to_sym

        if self.class.subscriptions.key?(name)
          raise NotImplementedError,
                "#{name} is a subscription — WebSocket dispatch is not yet implemented"
        end

        escape = :"call_#{name}"
        if respond_to?(escape, true)
          BSV.logger&.debug { "[Protocol] #{self.class.name} :#{name} → escape hatch" }
          return rescuing_transport_errors { kwargs.empty? ? send(escape, *) : send(escape, *, **kwargs) }
        end

        default_call(name, *, **kwargs)
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
      # Transport failures (see +TRANSPORT_ERRORS+) are returned as a failed
      # +ProtocolResponse+ rather than raised.
      #
      # @param command_name [Symbol] registered command name
      # @param args   [Array]  positional path parameters
      # @param kwargs [Hash]   named path parameters (and optional +:body+)
      # @return [ProtocolResponse]
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

        BSV.logger&.debug { "[Protocol] #{defn[:method].upcase} #{origin}#{path}" }

        rescuing_transport_errors { build_response(execute(uri, request), defn[:response]) }
      end

      # Whether a credential is configured, via +auth:+ or the legacy +api_key:+.
      #
      # @return [Boolean]
      def authenticated?
        return true if @auth != :none

        !@api_key.to_s.empty?
      end

      # Describes the protocol without exposing credentials. Built from an
      # allow-list (class, origin, auth status) because the path and query of a
      # base URL, and subclass state such as callback tokens, can carry secrets.
      #
      # @return [String]
      def to_s
        "#<#{self.class} origin=#{origin.inspect} auth=#{authenticated? ? 'authenticated' : 'unauthenticated'}>"
      end
      alias inspect to_s

      private

      # Scheme, host and non-default port of the base URL; never userinfo, path
      # or query.
      def origin
        uri = URI.parse(@base_url)
        return '(unparseable)' unless uri.scheme && uri.host

        port = uri.port == uri.default_port ? '' : ":#{uri.port}"
        "#{uri.scheme}://#{uri.host}#{port}"
      rescue URI::InvalidURIError
        '(unparseable)'
      end

      # Converts transport failures raised by the block into a failed
      # +ProtocolResponse+. +ArgumentError+ and other caller or programmer errors
      # are not in +TRANSPORT_ERRORS+ and propagate.
      def rescuing_transport_errors
        yield
      rescue *TRANSPORT_ERRORS => e
        # Only the class is logged: a parser error's message carries server
        # bytes, which a hostile server could use to reflect request headers.
        BSV.logger&.debug { "[Protocol] transport error: #{e.class}" }
        ProtocolResponse.new(nil, http_success: false, error_message: transport_error_message(e))
      end

      # The error text is sanitised because +Net::HTTPBadResponse+ and similar
      # embed raw bytes from the server.
      def transport_error_message(error)
        text = BSV::Network::Util.service_text(error.message) || error.class.name
        message = "transport error: #{error.class}: #{text}"
        return message if NOT_SENT_ERRORS.any? { |klass| error.is_a?(klass) }

        "#{message} (the request may have reached the service)"
      end

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
      # Auth header dispatch (in priority order):
      # 1. +auth:+ config hash takes precedence over the legacy +api_key:+ shorthand.
      # 2. +{ bearer: 'token' }+ → +Authorization: Bearer token+
      # 3. +{ api_key: 'key', header: 'X-Custom' }+ → +X-Custom: key+
      # 4. +{ api_key: 'key' }+ → +Authorization: key+ (no Bearer prefix)
      # 5. +auth: :none+ or no auth at all → no Authorization header set
      # 6. Legacy +api_key:+ (no auth: provided) → +Authorization: Bearer api_key+
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

        apply_auth(request)

        if body && request.respond_to?(:body=)
          request.body = body
          request.content_type = 'application/json' unless request.content_type
        end
        request
      end

      # Applies the auth header to the request based on the +auth:+ config or
      # the legacy +api_key:+ shorthand.
      #
      # @param request [Net::HTTPRequest]
      def apply_auth(request)
        # auth: config takes precedence over legacy api_key:
        if @auth != :none
          auth = @auth
          if auth[:bearer]
            request['Authorization'] = "Bearer #{auth[:bearer]}"
          elsif auth[:api_key]
            header = auth[:header] || 'Authorization'
            request[header] = auth[:api_key]
          end
        elsif @api_key
          # Legacy shorthand: api_key: without auth: sends Bearer
          request['Authorization'] = "Bearer #{@api_key}"
        end
      end

      # Normalises the +auth+ argument so that +nil+ and empty hashes are
      # stored as +:none+, giving a single canonical sentinel value for
      # "no authentication".
      #
      # @param auth [Hash, Symbol, nil]
      # @return [Hash, Symbol]
      def normalise_auth(auth)
        return :none if auth.nil?
        return :none if auth == :none
        return :none if auth.is_a?(Hash) && (auth.empty? || (auth[:bearer].nil? && auth[:api_key].nil?))

        auth
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
          # max_retries: 0 because Net::HTTP re-sends an idempotent request (GET) once
          # after a read timeout, doubling the wait. That retry exists for stale
          # keep-alive connections, which cannot occur here: every request opens a
          # fresh connection.
          Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https',
                                                  open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT,
                                                  write_timeout: WRITE_TIMEOUT, max_retries: 0) do |http|
            http.request(request)
          end
        end
      end

      # Wraps an HTTP response in a +ProtocolResponse+, applying the response
      # handler on 2xx bodies.
      #
      # On 2xx responses, the handler is applied and the result stored in +data+.
      # If the handler raises +JSON::ParserError+ or +TypeError+, the response
      # is marked as an error with the exception message.
      #
      # On non-2xx responses, the raw body is stored as +error_message+.
      #
      # @param response [Net::HTTPResponse]
      # @param handler  [Symbol, #call]
      # @return [ProtocolResponse]
      def build_response(response, handler)
        result = if response.is_a?(Net::HTTPSuccess)
                   begin
                     data = apply_handler(response.body, handler)
                     ProtocolResponse.new(response, data: data)
                   rescue JSON::ParserError, TypeError => e
                     ProtocolResponse.new(response, http_success: false,
                                                    error_message: "JSON/response error: #{e.message}")
                   end
                 else
                   ProtocolResponse.new(response, error_message: response.body)
                 end

        # The error text is not logged: it is the raw body, which a service may
        # use to reflect request headers such as the API key, and which need
        # not be valid UTF-8.
        BSV.logger&.debug { "[Protocol] HTTP #{response.code} → http_success=#{result.http_success?}" }

        result
      end

      # Applies the response handler to a raw body string.
      #
      # Exceptions from JSON parsing or type mismatches propagate to the caller
      # (+build_response+) which handles them uniformly.
      #
      # @param body    [String, nil]
      # @param handler [Symbol, #call]
      # @return [Object]
      def apply_handler(body, handler)
        return body if body.nil?

        case handler
        when :raw
          body
        when :json
          JSON.parse(body)
        when :json_array
          parsed = JSON.parse(body)
          # Some providers (e.g. WoC) wrap arrays in { "result": [...] }
          parsed = parsed['result'] if parsed.is_a?(Hash) && parsed.key?('result')
          raise TypeError, "expected Array, got #{parsed.class}" unless parsed.is_a?(Array)

          parsed
        else
          raise ArgumentError, "unsupported response handler: #{handler.inspect}" unless handler.respond_to?(:call)

          handler.call(body)
        end
      end
    end
  end
end
