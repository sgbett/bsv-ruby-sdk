# frozen_string_literal: true

require 'set'

module BSV
  module Network
    # Abstract base class for network endpoint implementations.
    #
    # Subclasses declare supported commands via the +provides+ class macro and
    # implement each command as a +call_<name>+ instance method. The base class
    # handles dispatch, capability validation, and result construction.
    #
    # == Example
    #
    #   class MyProvider < BSV::Network::Provider
    #     provides :get_tx, :broadcast
    #
    #     def call_get_tx(txid)
    #       # ... fetch transaction ...
    #       success(tx)
    #     end
    #
    #     def call_broadcast(tx)
    #       # ... submit to network ...
    #       error('rejected', retryable: false)
    #     end
    #   end
    #
    # == Inheritance
    #
    # Capabilities are inherited. If a parent class provides +:get_tx+ and a
    # child class provides +:broadcast+, the child's +capabilities+ includes
    # both symbols.
    #
    # == HTTP client injection
    #
    # Pass +http_client:+ to the constructor for testability. Subclasses access
    # it via +@http_client+. The client must respond to +#request(uri, request)+.
    class Provider
      # Returns the set of command names this class (and its ancestors) support.
      #
      # @return [Set<Symbol>] frozen set of supported command names
      def self.capabilities
        if superclass.respond_to?(:capabilities)
          superclass.capabilities | own_capabilities
        else
          own_capabilities
        end.freeze
      end

      # Declare one or more commands this provider supports.
      #
      # May be called multiple times; declarations accumulate (union semantics).
      # String arguments are coerced to Symbols.
      #
      # @param command_names [Array<Symbol, String>] supported command names
      def self.provides(*command_names)
        command_names.each do |name|
          own_capabilities << name.to_sym
        end
      end

      # @param http_client [#request, nil] injectable HTTP client for testing
      # @param options [Hash] arbitrary options forwarded to subclass
      def initialize(http_client: nil, **options)
        @http_client = http_client
        @options = options
      end

      # Dispatch a command to the corresponding +call_<name>+ method.
      #
      # @param command_name [Symbol, String] the command to invoke
      # @param args [Array] arguments forwarded to the handler method
      # @return [Result::Success, Result::Error, Result::NotFound]
      # @raise [ArgumentError] when the command is not in {.capabilities}
      def call(command_name, *args)
        sym = command_name.to_sym
        unless self.class.capabilities.include?(sym)
          raise ArgumentError,
                "#{self.class} does not provide command :#{sym}. " \
                "Provided: #{self.class.capabilities.to_a.sort.inspect}"
        end

        send(:"call_#{sym}", *args)
      end

      private

      # Returns a {Result::Success} carrying the given data.
      #
      # @param data [Object] the successful result value
      # @return [Result::Success]
      def success(data)
        Result::Success.new(data: data)
      end

      # Returns a {Result::Error} with a message and optional retryable flag.
      #
      # @param message [String] human-readable error description
      # @param retryable [Boolean] whether another provider may succeed (default: false)
      # @return [Result::Error]
      def error(message, retryable: false)
        Result::Error.new(message, retryable: retryable)
      end

      # Returns a {Result::NotFound} indicating the resource does not exist.
      #
      # @return [Result::NotFound]
      def not_found
        Result::NotFound.new
      end

      # Lazy-initialised per-class capability Set (not shared with ancestors).
      def self.own_capabilities
        @own_capabilities ||= Set.new
      end
      private_class_method :own_capabilities
    end
  end
end
