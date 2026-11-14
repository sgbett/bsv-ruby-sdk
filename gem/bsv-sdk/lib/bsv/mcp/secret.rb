# frozen_string_literal: true

module BSV
  module MCP
    # Wraps a credential so that it cannot leak through +inspect+, +to_s+ or
    # JSON serialisation of the objects that hold it (the server context, the
    # +::MCP::Server+ instance, error output).
    #
    # The value is unwrapped explicitly with {#reveal} only where the protocol
    # that needs it is built.
    class Secret
      REDACTED = '[REDACTED]'

      # Unwraps a {Secret}, passing any other value through unchanged.
      #
      # @param value [Secret, String, nil]
      # @return [String, nil]
      def self.reveal(value)
        value.is_a?(Secret) ? value.reveal : value
      end

      # @param value [String]
      def initialize(value)
        @value = value.to_s.dup.freeze
      end

      # @return [String] the wrapped credential
      def reveal
        @value
      end

      def inspect
        "#<#{self.class.name} #{REDACTED}>"
      end

      def to_s
        REDACTED
      end

      def to_json(*)
        REDACTED.to_json
      end
    end
  end
end
