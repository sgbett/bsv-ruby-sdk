# frozen_string_literal: true

module BSV
  module Wallet
    class Client
      # Blockchain and network data methods for {Client}.
      module NetworkOps
        # Returns the current blockchain height.
        #
        # Requires a substrate — raises {UnsupportedActionError} locally.
        #
        # @return [Hash] { height: Integer }
        def get_height(args = {}, originator: nil)
          return @substrate.get_height(args, originator: originator) if @substrate

          raise UnsupportedActionError, 'get_height requires a remote substrate'
        end

        # Returns the block header at the given height.
        #
        # Requires a substrate — raises {UnsupportedActionError} locally.
        #
        # @param args [Hash]
        # @option args [Integer] :height block height
        # @return [Hash] { header: String } 80-byte hex-encoded block header
        def get_header_for_height(args, originator: nil)
          return @substrate.get_header_for_height(args, originator: originator) if @substrate

          raise UnsupportedActionError, 'get_header_for_height requires a remote substrate'
        end

        # Returns the network this wallet is configured for.
        #
        # @return [Hash] { network: String } 'mainnet' or 'testnet'
        def get_network(args = {}, originator: nil)
          return @substrate.get_network(args, originator: originator) if @substrate

          { network: @network }
        end

        # Returns the wallet version string.
        #
        # @return [Hash] { version: String } in vendor-major.minor.patch format
        def get_version(args = {}, originator: nil)
          return @substrate.get_version(args, originator: originator) if @substrate

          { version: "bsv-wallet-#{BSV::Wallet::VERSION}" }
        end
      end
    end
  end
end
