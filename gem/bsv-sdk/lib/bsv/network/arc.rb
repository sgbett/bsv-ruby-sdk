# frozen_string_literal: true

module BSV
  module Network
    # @deprecated Use {BSV::Network::Protocols::ARC} directly instead.
    #   The facade converted clean Result objects into exceptions — every
    #   consumer immediately caught them and converted back to data.
    #   Use the protocol layer, which returns Result objects natively.
    class ARC
      # Raised when deprecated facade classes are instantiated.
      class DeprecationError < StandardError; end

      MESSAGE = 'BSV::Network::ARC is deprecated. ' \
        'Use BSV::Network::Protocols::ARC directly — it returns Result objects ' \
        'instead of raising exceptions. See BSV::Network::Protocols::ARC for usage.'

      def self.default(**)
        raise DeprecationError, MESSAGE
      end

      def initialize(*)
        raise DeprecationError, MESSAGE
      end
    end
  end
end
