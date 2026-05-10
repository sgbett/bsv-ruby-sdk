# frozen_string_literal: true

module BSV
  module Network
    # @deprecated Use {BSV::Network::Protocols::WoCREST} directly instead.
    #   The facade converted clean ProtocolResponse objects into exceptions — every
    #   consumer immediately caught them and converted back to data.
    #   Use the protocol layer, which returns ProtocolResponse objects natively.
    class WhatsOnChain
      # Raised when deprecated facade classes are instantiated.
      class DeprecationError < StandardError; end

      MESSAGE = 'BSV::Network::WhatsOnChain is deprecated. ' \
                'Use BSV::Network::Protocols::WoCREST directly — it returns ProtocolResponse objects ' \
                'instead of raising exceptions. See BSV::Network::Protocols::WoCREST for usage.'

      def self.default(**)
        raise DeprecationError, MESSAGE
      end

      def initialize(*)
        raise DeprecationError, MESSAGE
      end
    end
  end
end
