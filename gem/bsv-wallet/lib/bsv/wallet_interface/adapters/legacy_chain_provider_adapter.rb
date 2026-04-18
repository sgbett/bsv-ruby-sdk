# frozen_string_literal: true

module BSV
  module Wallet
    # Forward adapter: wraps a legacy {ChainProvider} as a {BSV::Network::Provider}.
    #
    # Registers capabilities for +:get_utxos+, +:get_tx+, and +:current_height+,
    # mapping ChainProvider method names to Registry command names and wrapping
    # return values in +Result::Success+ / +Result::Error+.
    #
    # Any exception raised by the underlying provider is caught and returned as
    # a non-retryable +Result::Error+.
    #
    # @example
    #   woc = BSV::Wallet::WhatsOnChainProvider.new
    #   adapter = BSV::Wallet::LegacyChainProviderAdapter.new(woc)
    #   registry = BSV::Network::Registry.new
    #   registry.register(adapter)
    class LegacyChainProviderAdapter < BSV::Network::Provider
      provides :get_utxos, :get_tx, :current_height

      # @param chain_provider [#get_utxos, #get_transaction, #get_height] legacy chain provider
      def initialize(chain_provider)
        super()
        unless ENV['BSV_SUPPRESS_DEPRECATIONS']
          self.class.instance_variable_get(:@deprecation_warnings) ||
            self.class.instance_variable_set(:@deprecation_warnings, {})
          unless self.class.instance_variable_get(:@deprecation_warnings)[:new]
            warn '[DEPRECATION] chain_provider: is deprecated. ' \
                 'Pass a BSV::Network::Registry via network: instead. ' \
                 'See https://github.com/sgbett/bsv-ruby-sdk/issues/498'
            self.class.instance_variable_get(:@deprecation_warnings)[:new] = true
          end
        end
        @chain_provider = chain_provider
      end

      private

      # Fetch UTXOs for a given address.
      #
      # @param address [String] BSV address
      # @return [Result::Success, Result::Error]
      def call_get_utxos(address)
        data = @chain_provider.get_utxos(address)
        success(data)
      rescue StandardError => e
        error(e.message, retryable: false)
      end

      # Fetch a raw transaction by TXID.
      #
      # Maps +:get_tx+ to +ChainProvider#get_transaction+.
      #
      # @param txid [String] transaction ID (hex)
      # @return [Result::Success, Result::Error]
      def call_get_tx(txid)
        data = @chain_provider.get_transaction(txid)
        success(data)
      rescue StandardError => e
        error(e.message, retryable: false)
      end

      # Return the current blockchain height.
      #
      # Maps +:current_height+ to +ChainProvider#get_height+.
      #
      # @return [Result::Success, Result::Error]
      def call_current_height
        height = @chain_provider.get_height
        success(height)
      rescue StandardError => e
        error(e.message, retryable: false)
      end
    end
  end
end
