# frozen_string_literal: true

module BSV
  module Wallet
    class Client
      # Blockchain and network data methods for {Client}.
      module Network
        # Returns the current blockchain height.
        #
        # Delegates to the substrate when configured. Falls back to the local
        # chain data source when present. Raises {UnsupportedActionError} when
        # neither is available.
        #
        # @return [Hash] { height: Integer }
        def get_height(args = {}, originator: nil)
          return @substrate.get_height(args, originator: originator) if @substrate

          raise UnsupportedActionError, 'get_height requires a chain_data_source or remote substrate' unless @chain_data_source

          { height: @chain_data_source.current_height }
        end

        # Returns the block header at the given height.
        #
        # Delegates to the substrate when configured; falls back to the local
        # chain data source otherwise.
        #
        # Note: BRC-100 specifies +{ header: String }+ (80-byte raw hex), but the
        # Ruby SDK returns the richer WoC JSON hash (containing +hash+,
        # +merkleroot+, +previousblockhash+, +time+, +nonce+, +bits+,
        # +version+, and +height+) under the +header+ key. This is strictly more
        # useful and avoids error-prone byte-order reassembly; there is no
        # cross-SDK precedent to conflict with.
        #
        # @param args [Hash]
        # @option args [Integer] :height block height (must be >= 0)
        # @return [Hash] { header: Hash } WoC block header JSON
        def get_header_for_height(args, originator: nil)
          return @substrate.get_header_for_height(args, originator: originator) if @substrate

          raise UnsupportedActionError, 'get_header_for_height requires a chain_data_source or remote substrate' unless @chain_data_source

          height = args[:height]
          raise InvalidParameterError.new('height', 'a non-negative Integer') unless height.is_a?(Integer) && !height.negative?

          { header: @chain_data_source.get_block_header(height) }
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
