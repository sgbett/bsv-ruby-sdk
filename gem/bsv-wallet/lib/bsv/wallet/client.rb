# frozen_string_literal: true

require_relative 'client/authentication_ops'
require_relative 'client/crypto'
require_relative 'client/identity_ops'
require_relative 'client/network_ops'
require_relative 'client/transaction_ops'

module BSV
  module Wallet
    # BRC-100 wallet implementation.
    #
    # All 28 BRC-100 methods are implemented directly — the 9 crypto operations
    # are inlined here, with substrate delegation wired at the top of each
    # method. No inheritance; behaviour is fully self-contained.
    #
    # @example Create a simple transaction
    #   client = BSV::Wallet::Client.new(private_key)
    #   result = client.create_action({
    #     description: 'Pay invoice',
    #     outputs: [{ locking_script: '76a914...88ac', satoshis: 1000,
    #                 output_description: 'Payment' }]
    #   })
    class Client
      include BRC100::Interface
      include AuthenticationOps
      include Crypto
      include IdentityOps
      include NetworkOps
      include TransactionOps

      # @return [KeyDeriver] the underlying key deriver
      attr_reader :key_deriver

      # @return [StorageAdapter] the underlying persistence adapter
      attr_reader :storage

      # @return [String] the network ('mainnet' or 'testnet')
      attr_reader :network

      # @return [ProofStore] the merkle proof persistence store
      attr_reader :proof_store

      # @return [#broadcast, nil] the optional broadcaster (responds to #broadcast(tx))
      attr_reader :broadcaster

      # @return [BroadcastQueue] the broadcast queue used to dispatch transactions
      attr_reader :broadcast_queue

      # @return [Interface, nil] the optional substrate for remote wallet delegation
      attr_reader :substrate

      # @param key [BSV::Primitives::PrivateKey, String, KeyDeriver] signing key
      # @param storage [StorageAdapter] persistence adapter (default: FileStore).
      #   Use +storage: MemoryStore.new+ for tests.
      # @param network [String] 'mainnet' (default) or 'testnet'
      # @param proof_store [ProofStore, nil] merkle proof store (default: LocalProofStore backed by storage)
      # @param http_client [#request, nil] injectable HTTP client for certificate issuance
      # @param fee_estimator [FeeEstimator, nil] optional fee estimator
      # @param coin_selector [CoinSelector, nil] optional coin selector
      # @param change_generator [ChangeGenerator, nil] optional change generator
      # @param broadcaster [#broadcast, nil] optional broadcaster
      # @param broadcast_queue [BroadcastQueue, nil] optional broadcast queue; defaults to InlineQueue
      # @param substrate [Interface, nil] optional remote wallet substrate
      def initialize(
        key,
        storage: FileStore.new,
        network: 'mainnet',
        proof_store: nil,
        http_client: nil,
        fee_estimator: nil,
        coin_selector: nil,
        change_generator: nil,
        broadcaster: nil,
        broadcast_queue: nil,
        substrate: nil
      )
        @key_deriver = key.is_a?(KeyDeriver) ? key : KeyDeriver.new(key)
        @substrate = substrate
        @storage = storage
        @network = network
        @proof_store = proof_store || LocalProofStore.new(storage)
        @http_client = http_client
        @broadcaster = broadcaster
        @pending = {}
        @pending_by_txid = {}
        @injected_fee_estimator    = fee_estimator
        @injected_coin_selector    = coin_selector
        @injected_change_generator = change_generator
        @broadcast_queue = broadcast_queue || InlineQueue.new(
          storage: @storage,
          broadcaster: @broadcaster
        )
      end

      # Returns +true+ when broadcast is available.
      def broadcast_enabled?
        @broadcast_queue.broadcast_enabled?
      end

      # Raises {UnsupportedActionError}.
      def sync_utxos
        raise UnsupportedActionError, 'sync_utxos requires a remote substrate or custom integration'
      end

      # --- UTXO Pool & Settings ---

      # Returns the total spendable satoshis across all baskets (or a named basket).
      #
      # @param basket [String, nil] the basket to total, or +nil+ for all baskets
      # @return [Integer] sum of all spendable output values
      def balance(basket: nil)
        @storage.find_spendable_outputs(basket: basket).sum { |o| o[:satoshis].to_i }
      end

      # Returns the total satoshis of outputs the wallet can automatically spend.
      #
      # @param basket [String, nil] restrict to a named basket, or +nil+ for all
      # @return [Integer] total auto-spendable satoshis
      def spendable_balance(basket: nil)
        @storage.find_spendable_outputs(basket: basket)
                .select { |o| (o[:derivation_prefix] && o[:derivation_suffix] && o[:sender_identity_key]) || o[:derivation_type]&.to_s == 'identity' }
                .sum { |o| o[:satoshis].to_i }
      end

      # Configures the target UTXO pool parameters for change generation.
      #
      # @param count [Integer] desired number of spendable UTXOs in 'default' basket
      # @param satoshis [Integer] desired average value per UTXO in satoshis
      def set_wallet_change_params(count:, satoshis:)
        raise InvalidParameterError.new('count', 'a positive Integer') unless count.is_a?(Integer) && count.positive?
        raise InvalidParameterError.new('satoshis', 'a positive Integer') unless satoshis.is_a?(Integer) && satoshis.positive?

        @storage.store_setting('change_params', { count: count, satoshis: satoshis })
      end

      # Creates a UTXO pool for high-frequency transaction pre-allocation.
      #
      # @param name [String] pool identifier (basket will be +"pool:<name>"+)
      # @param target_count [Integer] desired number of UTXOs (default 20)
      # @param target_satoshis [Integer] desired satoshis per UTXO (default 10_000)
      # @param low_water_mark [Float] replenishment trigger fraction (default 0.5)
      # @return [LocalPool]
      def utxo_pool(name:, target_count: 20, target_satoshis: 10_000, low_water_mark: 0.5)
        basket = "pool:#{name}"
        Validators.validate_basket!(basket)
        raise WalletError, 'utxo_pool requires a broadcaster for replenishment' unless broadcast_enabled?

        threshold = (target_count * low_water_mark).ceil
        pool = LocalPool.new(
          name: name,
          storage: @storage,
          wallet_client: self,
          target_count: target_count,
          target_satoshis: target_satoshis,
          low_water_mark: threshold
        )
        worker = ReplenishmentWorker.new(
          pool: pool,
          wallet_client: self
        )
        pool.replenisher = worker
        worker.start
        pool
      end

      private

      # --- Identity helpers ---

      def identity_address
        net = @network == 'testnet' ? :testnet : :mainnet
        @key_deriver.root_key.public_key.address(network: net)
      end

      def output_exists?(outpoint)
        @storage.find_outputs({ outpoint: outpoint, include_spent: true, limit: 1, offset: 0 }).any?
      end
    end
  end
end
