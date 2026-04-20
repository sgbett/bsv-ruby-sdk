# frozen_string_literal: true

module BSV
  module Wallet
    class Client
      # Authentication methods for {Client}.
      module AuthenticationOps
        # Checks whether the user is authenticated.
        #
        # @return [Hash] { authenticated: Boolean }
        def is_authenticated(args = {}, originator: nil)
          return @substrate.is_authenticated(args, originator: originator) if @substrate

          { authenticated: true }
        end

        # Waits until the user is authenticated.
        #
        # @return [Hash] { authenticated: true }
        def wait_for_authentication(args = {}, originator: nil)
          return @substrate.wait_for_authentication(args, originator: originator) if @substrate

          { authenticated: true }
        end
      end
    end
  end
end
