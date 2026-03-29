# frozen_string_literal: true

module BSV
  module Auth
    # Duck-typed interface for BRC-31 message transport.
    #
    # Concrete transports (HTTP, WebSocket, in-process, etc.) must implement
    # both methods. Include this module to get the default +NotImplementedError+
    # stubs — override in your implementation class.
    #
    # @example Minimal in-process transport for testing
    #   class DirectTransport
    #     include BSV::Auth::Transport
    #
    #     def initialize(peer)
    #       @peer = peer
    #     end
    #
    #     def send(message)
    #       @peer.handle_incoming_message(message)
    #     end
    #
    #     def on_data(&block)
    #       @on_data = block
    #     end
    #   end
    module Transport
      # Sends a message to the remote peer.
      #
      # @param message [Hash] the serialised auth message
      # @return [void]
      def send(_message)
        raise NotImplementedError, "#{self.class}#send not implemented"
      end

      # Registers a callback to be invoked when a message arrives.
      #
      # @yieldparam message [Hash] the incoming auth message
      # @return [void]
      def on_data(&_block)
        raise NotImplementedError, "#{self.class}#on_data not implemented"
      end
    end
  end
end
