# frozen_string_literal: true

module BSV
  module Network
    # A value object representing a declared network operation.
    #
    # Commands are registered at class level via {Command.define} and retrieved
    # via {Command.find} or {Command.all}. The registry is thread-safe.
    #
    # @example Define a command
    #   BSV::Network::Command.define(
    #     :broadcast,
    #     params: { tx: 'Transaction' },
    #     returns: 'Result::Success<BroadcastResponse>',
    #     description: 'Submit a transaction to the network'
    #   )
    class Command
      @commands = {}
      @mutex = Mutex.new

      attr_reader :name, :params, :returns, :description

      # Define and register a new command.
      #
      # @param name [Symbol, String] the command identifier; coerced to Symbol
      # @param params [Object] opaque metadata describing accepted parameters
      # @param returns [Object] opaque metadata describing the return value
      # @param description [String] human-readable description of the command
      # @return [Command] the newly registered (frozen) command
      # @raise [ArgumentError] if a command with the same name is already registered
      def self.define(name, params:, returns:, description:)
        sym = name.to_sym

        @mutex.synchronize do
          raise ArgumentError, "command :#{sym} already defined" if @commands.key?(sym)

          command = new(sym, params: params, returns: returns, description: description)
          @commands[sym] = command
          command
        end
      end

      # Returns a frozen copy of all registered commands.
      #
      # @return [Hash{Symbol => Command}]
      def self.all
        @mutex.synchronize { @commands.dup.freeze }
      end

      # Find a registered command by name.
      #
      # @param name [Symbol, String] the command identifier; coerced to Symbol
      # @return [Command, nil] the command, or nil if not found
      def self.find(name)
        @mutex.synchronize { @commands[name.to_sym] }
      end

      # Clear all registered commands.
      #
      # Intended for use in tests only.
      def self.reset!
        @mutex.synchronize { @commands.clear }
      end

      private_class_method :new

      def initialize(name, params:, returns:, description:)
        @name = name
        @params = params
        @returns = returns
        @description = description
        freeze
      end
    end
  end
end
