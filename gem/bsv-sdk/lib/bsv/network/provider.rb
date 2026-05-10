# frozen_string_literal: true

require 'set'

module BSV
  module Network
    # Provider is a named configuration container that hosts one or more Protocol
    # instances and dispatches commands to the appropriate protocol.
    #
    # Protocols are registered via a block DSL or by calling +#protocol+ directly
    # after construction. For each command symbol, the first-registered protocol
    # that serves it wins (first-registered-wins, no warning on duplicates).
    #
    # == Example
    #
    #   gorillapool = BSV::Network::Provider.new('GorillaPool') do |p|
    #     p.protocol Protocols::ARC,         base_url: 'https://arcade.gorillapool.io'
    #     p.protocol Protocols::Chaintracks, base_url: 'https://arcade.gorillapool.io'
    #     p.protocol Protocols::Ordinals,    base_url: 'https://ordinals.gorillapool.io'
    #   end
    #
    #   result = gorillapool.call(:broadcast, tx)
    #   result.success?  # => true
    class Provider
      attr_reader :name, :auth, :rate_limit

      # @param name       [String]        human-readable provider name (e.g. 'GorillaPool')
      # @param auth       [Hash, Symbol]  authentication config or +:none+ (default: +:none+).
      #                                   An empty hash or +nil+ is treated as +:none+.
      # @param rate_limit [Numeric, nil]  maximum requests per second (+nil+ = unlimited)
      # @param block      [Proc]          optional configuration block — yields +self+
      def initialize(name, auth: :none, rate_limit: nil, &block)
        @name           = name
        @auth           = normalise_auth(auth)
        @rate_limit     = rate_limit
        @protocols      = []
        @command_index  = {}
        block&.call(self)
      end

      # Returns +true+ when the provider is configured with authentication
      # credentials (i.e. +auth+ is not +:none+ and not an empty hash).
      #
      # @return [Boolean]
      def authenticated?
        @auth != :none
      end

      # Registers a protocol class with the provider.
      #
      # The class is instantiated with the supplied +kwargs+. Its commands are
      # indexed: each command not yet in the index is mapped to this instance.
      # Commands already in the index are left unchanged (first-registered wins).
      #
      # The provider remains mutable — +protocol+ may be called after block
      # execution.
      #
      # @param klass  [Class]  a Protocol subclass
      # @param kwargs [Hash]   keyword arguments forwarded to +klass.new+
      # @return [Protocol] the newly created protocol instance
      def protocol(klass, **kwargs)
        instance = klass.new(**kwargs)
        @protocols << instance
        klass.commands.each do |cmd|
          @command_index[cmd] ||= instance
        end
        instance
      end

      # Returns a frozen copy of the registered protocol instances, in
      # registration order.
      #
      # @return [Array<Protocol>]
      def protocols
        @protocols.dup.freeze
      end

      # Returns the set of all command symbols available on this provider.
      #
      # @return [Set<Symbol>]
      def commands
        Set.new(@command_index.keys)
      end

      # Returns the protocol instance that serves a given command, or nil if no
      # registered protocol handles it.
      #
      # @param command_name [Symbol, String]
      # @return [Protocol, nil]
      def protocol_for(command_name)
        @command_index[command_name.to_sym]
      end

      # Returns a hash mapping each protocol instance to the sorted list of
      # commands it actually serves within this provider (respecting
      # first-registered-wins — a protocol that lost a command to an earlier
      # registration is not listed for that command).
      #
      # Protocols that serve no commands in this provider are omitted.
      #
      # @return [Hash{Protocol => Array<Symbol>}]
      def capability_matrix
        matrix = {}
        @protocols.each do |proto|
          served = proto.class.commands.select { |cmd| @command_index[cmd] == proto }
          matrix[proto] = served.sort unless served.empty?
        end
        matrix
      end

      # Returns a human-readable representation of the provider.
      #
      # @return [String]
      def to_s
        protocol_summary = @protocols.map { |p| p.class.name&.split('::')&.last || p.class.to_s }.join(', ')
        auth_status      = authenticated? ? 'authenticated' : 'unauthenticated'
        rate_part        = @rate_limit.nil? ? '' : " rate_limit=#{@rate_limit}"
        "#<#{self.class} name=#{@name.inspect} auth=#{auth_status}#{rate_part} protocols=[#{protocol_summary}]>"
      end
      alias inspect to_s

      # Dispatches a command to the first-registered protocol that serves it.
      #
      # @param command_name [Symbol, String] command to invoke
      # @param args   [Array]  positional arguments forwarded to the protocol
      # @param kwargs [Hash]   keyword arguments forwarded to the protocol
      # @return [ProtocolResponse]
      # @raise [ArgumentError] when no registered protocol serves the command
      def call(command_name, *args, **kwargs)
        sym      = command_name.to_sym
        instance = @command_index[sym]
        raise ArgumentError, "#{@name} does not provide command :#{sym}" unless instance

        instance.call(sym, *args, **kwargs)
      end

      private

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
    end
  end
end
