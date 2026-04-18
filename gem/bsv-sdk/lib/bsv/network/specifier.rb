# frozen_string_literal: true

module BSV
  module Network
    # Controls which commands a provider handles within a registry registration.
    #
    # At most one of +only:+, +except:+, or +filter:+ may be provided.
    # Providing more than one raises +ArgumentError+ at construction.
    #
    # @example Allow everything (default)
    #   Specifier.new.allows?(:broadcast)  # => true
    #
    # @example Allowlist
    #   Specifier.new(only: [:broadcast]).allows?(:broadcast)  # => true
    #   Specifier.new(only: [:broadcast]).allows?(:get_tx)     # => false
    #
    # @example Blocklist
    #   Specifier.new(except: [:broadcast]).allows?(:broadcast) # => false
    #   Specifier.new(except: [:broadcast]).allows?(:get_tx)    # => true
    #
    # @example Custom predicate
    #   s = Specifier.new(filter: ->(cmd) { cmd.to_s.start_with?('get_') })
    #   s.allows?(:get_tx)    # => true
    #   s.allows?(:broadcast) # => false
    class Specifier
      # @param only   [Array<Symbol, String>, nil] allowlist of command names
      # @param except [Array<Symbol, String>, nil] blocklist of command names
      # @param filter [#call, nil] callable predicate; receives a Symbol command name
      def initialize(only: nil, except: nil, filter: nil)
        provided = [only, except, filter].count { |v| !v.nil? }
        raise ArgumentError, 'at most one of only:, except:, or filter: may be provided' if provided > 1

        @only   = coerce_symbols(only)
        @except = coerce_symbols(except)
        @filter = filter
      end

      # Returns true if the given command is permitted by this specifier.
      #
      # @param command_name [Symbol, String] the command to test
      # @return [Boolean]
      def allows?(command_name)
        name = command_name.to_sym

        return @filter.call(name) ? true : false if @filter
        return @only.include?(name)               if @only
        return !@except.include?(name)            if @except

        true
      end

      private

      def coerce_symbols(value)
        return nil if value.nil?

        value.map(&:to_sym)
      end
    end
  end
end
