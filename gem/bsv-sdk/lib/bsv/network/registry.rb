# frozen_string_literal: true

module BSV
  module Network
    # Runtime composition layer for network providers.
    #
    # The Registry holds a prioritised list of {Provider} instances, each paired
    # with a {Specifier} that controls which commands that provider handles. When
    # a command is dispatched via {#call}, the registry tries each eligible
    # provider in priority order and applies failover semantics based on the
    # {Result} type returned.
    #
    # == Registration
    #
    #   registry = BSV::Network::Registry.new
    #   registry.register(primary_provider, priority: 1)
    #   registry.register(fallback_provider, priority: 10, only: [:broadcast])
    #
    # == Dispatch semantics
    #
    # Providers are tried in ascending priority order (lower number = higher
    # precedence). Within the same priority, registration order (FIFO) is used.
    #
    # - {Result::Success}  — returned immediately; no further providers tried
    # - {Result::NotFound} — returned immediately; no further providers tried
    # - {Result::Error} with +retryable: true+  — next provider is tried
    # - {Result::Error} with +retryable: false+ — returned immediately
    # - All providers exhausted with retryable errors — last error returned
    # - No providers for command — raises {NoProviderError}
    #
    # == Exception wrapping
    #
    # If a provider raises a Ruby exception (rather than returning a Result),
    # the registry wraps it in a retryable {Result::Error} and tries the next
    # provider.
    class Registry
      # Raised when {#call} is invoked but no providers are registered for the
      # given command (either the registry is empty, or all specifiers exclude it).
      class NoProviderError < ArgumentError; end

      # @return [Array<Provider>] all registered provider instances (in insertion order, deduplicated by entry)
      def registered_providers
        @entries.map { |entry| entry[:provider] }
      end

      def initialize
        @entries = []
        @insertion_counter = 0
      end

      # Register a provider with optional routing control and priority.
      #
      # The same provider instance may be registered multiple times with
      # different specifiers — each registration is independent.
      #
      # @param provider [Provider] the provider to register
      # @param priority [Integer] lower numbers are tried first (default: 0)
      # @param only [Array<Symbol>, nil] allowlist passed to {Specifier}
      # @param except [Array<Symbol>, nil] blocklist passed to {Specifier}
      # @param filter [#call, nil] callable passed to {Specifier}
      # @return [self]
      def register(provider, priority: 0, only: nil, except: nil, filter: nil)
        specifier = Specifier.new(only: only, except: except, filter: filter)
        @entries << {
          provider: provider,
          specifier: specifier,
          priority: priority,
          order: @insertion_counter
        }
        @insertion_counter += 1
        self
      end

      # Dispatch a command to eligible providers, applying failover semantics.
      #
      # @param command_name [Symbol, String] the command to invoke
      # @param args [Array] arguments forwarded to the provider
      # @return [Result::Success, Result::Error, Result::NotFound]
      # @raise [NoProviderError] if no providers are registered for the command
      def call(command_name, *args)
        sym = command_name.to_sym
        candidates = providers_for(sym)

        raise NoProviderError, "no providers registered for command :#{sym}" if candidates.empty?

        last_error = nil

        candidates.map(&:first).each do |provider|
          result = safe_call(provider, sym, *args)

          return result if result.success?
          return result if result.not_found?
          return result if result.error? && !result.retryable?

          # Retryable error — record it and continue to next provider
          last_error = result
        end

        last_error
      end

      # Returns eligible providers for the given command, in priority order.
      #
      # A provider is eligible if:
      # 1. It declares the command in its capabilities
      # 2. Its specifier allows the command
      #
      # @param command_name [Symbol, String] the command to query
      # @return [Array<Array(Provider, Specifier)>] ordered list of [provider, specifier] pairs
      def providers_for(command_name)
        sym = command_name.to_sym

        eligible = @entries.select do |entry|
          entry[:provider].class.capabilities.include?(sym) &&
            entry[:specifier].allows?(sym)
        end

        sorted = eligible.sort_by { |entry| [entry[:priority], entry[:order]] }
        sorted.map { |entry| [entry[:provider], entry[:specifier]] }
      end

      # Returns a hash mapping each registered provider to the command names
      # it can handle, filtered by its specifier.
      #
      # When the same provider is registered multiple times (with different
      # specifiers), each registration appears as a separate entry with the
      # union of commands from all registrations attributed to the same object.
      # In practice the hash key is the provider object, so multiple
      # registrations of the same object are merged.
      #
      # @return [Hash{Provider => Array<Symbol>}] capability matrix
      def capability_matrix
        matrix = {}

        @entries.each do |entry|
          provider  = entry[:provider]
          specifier = entry[:specifier]

          commands = provider.class.capabilities.select { |cmd| specifier.allows?(cmd) }.sort

          existing = matrix[provider] || []
          matrix[provider] = (existing + commands).uniq.sort
        end

        matrix
      end

      private

      # Calls provider#call, wrapping any raised exception as a retryable error.
      #
      # @return [Result::Success, Result::Error, Result::NotFound]
      def safe_call(provider, command_name, *args)
        provider.call(command_name, *args)
      rescue StandardError => e
        Result::Error.new(e.message, retryable: true)
      end
    end
  end
end
