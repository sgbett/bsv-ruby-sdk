# frozen_string_literal: true

require_relative 'client/brc100/authentication'
require_relative 'client/brc100/crypto'
require_relative 'client/brc100/identity'
require_relative 'client/brc100/network'
require_relative 'client/brc100/transaction'

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
      include Interface::BRC100
      include Authentication
      include Crypto
      include Identity
      include Network
      include Transaction

      # @return [KeyDeriver] the underlying key deriver
      attr_reader :key_deriver

      # @return [Store] the underlying persistence adapter
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

      # @return [#current_height, #get_block_header, #fetch_utxos, #fetch_transaction, nil]
      #   optional chain data source for SPV and block header lookups
      attr_reader :chain_data_source

      # @param key [BSV::Primitives::PrivateKey, String, KeyDeriver] signing key
      # @param storage [Store] persistence adapter (default: Store::File.new)
      # @param allow_memory_store [Boolean] set +true+ to suppress the MemoryStore safety guard
      # @param network [String] 'mainnet' (default) or 'testnet'
      # @param proof_store [ProofStore, nil] merkle proof store (default: LocalProofStore backed by storage)
      # @param http_client [#request, nil] injectable HTTP client for certificate issuance
      # @param fee_estimator [FeeEstimator, nil] optional fee estimator
      # @param coin_selector [CoinSelector, nil] optional coin selector
      # @param change_generator [ChangeGenerator, nil] optional change generator
      # @param broadcaster [#broadcast, nil] optional broadcaster
      # @param broadcast_queue [BroadcastQueue, nil] optional broadcast queue; defaults to BroadcastQueue::Inline
      # @param substrate [Interface, nil] optional remote wallet substrate
      # @param chain_data_source [#current_height, #get_block_header, #fetch_utxos, #fetch_transaction, nil]
      #   optional chain data source for SPV and block header lookups
      def initialize(
        key,
        storage: Store::File.new,
        network: 'mainnet',
        proof_store: nil,
        http_client: nil,
        fee_estimator: nil,
        coin_selector: nil,
        change_generator: nil,
        broadcaster: nil,
        broadcast_queue: nil,
        substrate: nil,
        chain_data_source: nil,
        allow_memory_store: false
      )
        if storage.is_a?(Store::Memory) && !storage.is_a?(Store::File) && !allow_memory_store
          raise ArgumentError,
                'MemoryStore is not a safe storage adapter for wallets. ' \
                'See: https://sgbett.github.io/bsv-ruby-sdk/gems/wallet/#storage-adapters'
        end

        @key_deriver = key.is_a?(KeyDeriver) ? key : KeyDeriver.new(key)
        @substrate = substrate
        @chain_data_source = chain_data_source
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
        @broadcast_queue = broadcast_queue || BroadcastQueue::Inline.new(
          storage: @storage,
          broadcaster: @broadcaster
        )
      end

      # Returns +true+ when broadcast is available.
      def broadcast_enabled?
        @broadcast_queue.broadcast_enabled?
      end

      # Discovers UTXOs on-chain for the wallet's identity address and imports
      # any that are not already in local storage.
      #
      # Requires either a substrate or a chain_data_source. When both are present,
      # the substrate takes priority.
      #
      # @return [Integer] number of UTXOs imported (0 if nothing new)
      # @raise [UnsupportedActionError] when neither substrate nor chain_data_source is set
      # @raise [WalletError] when a fetched transaction has an out-of-bounds tx_pos
      def sync_utxos
        return @substrate.sync_utxos if @substrate

        raise UnsupportedActionError, 'sync_utxos requires a chain_data_source or remote substrate' unless @chain_data_source

        address = identity_address
        utxos = @chain_data_source.fetch_utxos(address)
        return 0 if utxos.empty?

        # Group UTXOs by tx_hash to minimise WoC API calls — rate limiting
        # is aggressive and penalties are harsh, so one fetch per transaction
        # is far better than one fetch per UTXO.
        tx_cache = {}
        new_utxos = utxos.reject { |u| output_exists?("#{u.tx_hash}.#{u.tx_pos}") }
        return 0 if new_utxos.empty?

        new_utxos.each do |utxo|
          tx = tx_cache[utxo.tx_hash] ||= @chain_data_source.fetch_transaction(utxo.tx_hash)

          pos = utxo.tx_pos
          unless pos.is_a?(Integer) && pos >= 0 && pos < tx.outputs.length
            raise WalletError, "Invalid tx_pos #{pos.inspect} for #{utxo.tx_hash} (#{tx.outputs.length} outputs)"
          end

          output = tx.outputs[pos]
          output_satoshis = output.satoshis

          # The transaction output is the authoritative source for satoshis —
          # a mismatch with the UTXO API would produce invalid sighashes.
          if !utxo.satoshis.nil? && utxo.satoshis != output_satoshis
            raise WalletError,
                  "UTXO value mismatch for #{utxo.tx_hash}.#{pos}: " \
                  "chain reported #{utxo.satoshis}, tx output is #{output_satoshis}"
          end

          locking_script_hex = output.locking_script.to_hex
          outpoint = "#{utxo.tx_hash}.#{utxo.tx_pos}"

          @storage.store_output({
                                  outpoint: outpoint,
                                  satoshis: output_satoshis,
                                  locking_script: locking_script_hex,
                                  basket: 'default',
                                  tags: [],
                                  derivation_type: :identity,
                                  state: :spendable,
                                  source_tx_hex: tx.to_hex
                                })
          @storage.store_transaction(utxo.tx_hash, tx.to_hex)
        end

        new_utxos.length
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
