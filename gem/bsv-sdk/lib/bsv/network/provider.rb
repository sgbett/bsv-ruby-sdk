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
      attr_reader :name

      # @param name  [String] human-readable provider name (e.g. 'GorillaPool')
      # @param block [Proc]   optional configuration block — yields +self+
      def initialize(name, &block)
        @name           = name
        @protocols      = []
        @command_index  = {}
        block&.call(self)
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

      # Dispatches a command to the first-registered protocol that serves it.
      #
      # @param command_name [Symbol, String] command to invoke
      # @param args   [Array]  positional arguments forwarded to the protocol
      # @param kwargs [Hash]   keyword arguments forwarded to the protocol
      # @return [Result::Success, Result::Error, Result::NotFound]
      # @raise [ArgumentError] when no registered protocol serves the command
      def call(command_name, *args, **kwargs)
        sym      = command_name.to_sym
        instance = @command_index[sym]
        raise ArgumentError, "#{@name} does not provide command :#{sym}" unless instance

        instance.call(sym, *args, **kwargs)
      end
    end
  end
end
