# frozen_string_literal: true

module BSV
  module Wallet
    # Duck-typed interface for blockchain data providers.
    #
    # Include this module in chain provider adapters and override all methods.
    # The default implementations raise NotImplementedError.
    #
    # @example Custom provider
    #   class MyChainProvider
    #     include BSV::Wallet::ChainProvider
    #
    #     def get_height
    #       # query your node/API
    #     end
    #
    #     def get_header(height)
    #       # return 80-byte hex block header
    #     end
    #   end
    module ChainProvider
      # Returns the current blockchain height.
      # @return [Integer]
      def get_height
        raise NotImplementedError, "#{self.class}#get_height not implemented"
      end

      # Returns the block header at the given height.
      # @param _height [Integer] block height
      # @return [String] 80-byte hex-encoded block header
      def get_header(_height)
        raise NotImplementedError, "#{self.class}#get_header not implemented"
      end

      # Returns unspent transaction outputs for the given address.
      # @param _address [String] BSV address
      # @return [Array<Hash>] array of hashes with :tx_hash, :tx_pos, :value keys
      def get_utxos(_address)
        raise NotImplementedError, "#{self.class}#get_utxos not implemented"
      end

      # Returns the raw transaction hex for the given txid.
      # @param _txid [String] transaction ID (hex)
      # @return [String] raw transaction hex string
      def get_transaction(_txid)
        raise NotImplementedError, "#{self.class}#get_transaction not implemented"
      end
    end
  end
end
