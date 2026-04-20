# frozen_string_literal: true

require 'securerandom'
require 'base64'
require 'net/http'
require 'json'
require 'set'
require 'uri'
require_relative 'client/crypto'

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
      include Crypto

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

      # --- Transaction Operations ---

      # Creates a new Bitcoin transaction.
      #
      # @param args [Hash] transaction parameters
      # @param _originator [String, nil] FQDN of the originating application
      # @return [Hash] finalised result or signable_transaction
      def create_action(args, originator: nil)
        return @substrate.create_action(args, originator: originator) if @substrate

        validate_create_action!(args)
        validate_broadcast_configuration!(args)

        send_with_txids = Array(args.dig(:options, :send_with))

        outputs = args[:outputs] || []
        inputs  = args[:inputs]

        if !send_with_txids.empty? && outputs.empty? && (inputs.nil? || inputs.empty?)
          raise WalletError, 'A broadcaster is required to use send_with' unless broadcast_enabled?

          return { send_with_results: broadcast_send_with(send_with_txids) }
        end

        if (inputs.nil? || inputs.empty?) && !outputs.empty? && (args[:auto_fund] || spendable_pool_eligible?)
          result = auto_fund_and_create(args, outputs)
          unless send_with_txids.empty?
            raise WalletError, 'A broadcaster is required to use send_with' unless broadcast_enabled?

            result[:send_with_results] = broadcast_send_with(send_with_txids)
          end
          return result
        end

        beef = parse_input_beef(args[:input_beef])
        tx = build_transaction(args, beef)

        if needs_signing?(args[:inputs])
          create_signable(tx, args, beef)
        else
          finalize_action(tx, args)
        end
      end

      # Signs a previously created signable transaction.
      #
      # @param args [Hash]
      # @option args [Hash] :spends map of input index to unlocking data
      # @option args [String] :reference base64 reference from create_action
      # @return [Hash] with :txid and :tx (BEEF bytes)
      def sign_action(args, originator: nil)
        return @substrate.sign_action(args, originator: originator) if @substrate

        reference = args[:reference]
        pending = @pending[reference]
        raise WalletError, 'Transaction not found for the given reference' unless pending

        tx = pending[:tx]
        apply_spends(tx, args[:spends])
        @pending.delete(reference)

        merged_args = if args[:options]
                        pending[:args].merge(options: (pending[:args][:options] || {}).merge(args[:options]))
                      else
                        pending[:args]
                      end

        validate_broadcast_configuration!(merged_args)

        finalize_action(tx, merged_args)
      end

      # Aborts a pending signable transaction.
      #
      # @param args [Hash]
      # @option args [String] :reference base64 reference to abort
      # @return [Hash] { aborted: true }
      def abort_action(args, originator: nil)
        return @substrate.abort_action(args, originator: originator) if @substrate

        reference = args[:reference]
        raise WalletError, 'Transaction not found for the given reference' unless @pending.key?(reference)

        pending_entry = @pending.delete(reference)
        txid = pending_entry[:tx]&.txid_hex
        @pending_by_txid.delete(txid) if txid
        rollback_pending_action(
          pending_entry[:locked_outpoints],
          pending_entry[:change_outpoints],
          txid,
          reference
        )
        { aborted: true }
      end

      # Lists stored actions matching the given labels.
      #
      # @param args [Hash]
      # @option args [Array<String>] :labels (required) labels to filter by
      # @return [Hash] { total_actions: Integer, actions: Array }
      def list_actions(args, originator: nil)
        return @substrate.list_actions(args, originator: originator) if @substrate

        validate_list_actions!(args)
        query = build_action_query(args)
        total = @storage.count_actions(query)
        actions = @storage.find_actions(query)
        { total_actions: total, actions: strip_action_fields(actions, args) }
      end

      # Lists spendable outputs in a basket.
      #
      # @param args [Hash]
      # @option args [String] :basket (required) basket name
      # @return [Hash] { total_outputs: Integer, outputs: Array }
      def list_outputs(args, originator: nil)
        return @substrate.list_outputs(args, originator: originator) if @substrate

        validate_list_outputs!(args)
        query = build_output_query(args)
        total = @storage.count_outputs(query)
        outputs = @storage.find_outputs(query)
        { total_outputs: total, outputs: strip_output_fields(outputs, args) }
      end

      # Removes an output from basket tracking.
      #
      # @param args [Hash]
      # @option args [String] :basket basket name
      # @option args [String] :output outpoint string
      # @return [Hash] { relinquished: true }
      def relinquish_output(args, originator: nil)
        return @substrate.relinquish_output(args, originator: originator) if @substrate

        Validators.validate_basket!(args[:basket])
        Validators.validate_outpoint!(args[:output])
        raise WalletError, 'Output not found' unless @storage.delete_output(args[:output])

        { relinquished: true }
      end

      # Accepts an incoming transaction for wallet internalization.
      #
      # @param args [Hash]
      # @option args [Array<Integer>] :tx Atomic BEEF-formatted transaction as byte array
      # @option args [Array<Hash>] :outputs output metadata
      # @option args [String] :description 5-50 char description
      # @return [Hash] { accepted: true }
      def internalize_action(args, originator: nil)
        return @substrate.internalize_action(args, originator: originator) if @substrate

        validate_internalize_action!(args)
        beef_binary = args[:tx].pack('C*')
        beef = BSV::Transaction::Beef.from_binary(beef_binary)

        raise WalletError, 'BEEF verification failed: the bundle is structurally invalid' unless beef.verify(nil)

        tx = extract_subject_transaction(beef)

        store_proofs_from_beef(beef)
        process_internalize_outputs(tx, args[:outputs])
        has_proof = !beef.find_bump(tx.txid).nil?
        store_action(tx, args, status: has_proof ? 'completed' : 'unproven')
        { accepted: true }
      end

      # --- Blockchain & Network Data ---

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

      # --- Authentication ---

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

      # --- Identity and Certificate Management ---

      # Acquires an identity certificate via direct storage or issuance.
      #
      # @param args [Hash]
      # @return [Hash] the stored certificate
      def acquire_certificate(args, originator: nil)
        return @substrate.acquire_certificate(args, originator: originator) if @substrate

        validate_acquire_certificate!(args)

        cert = if args[:acquisition_protocol] == 'issuance'
                 acquire_via_issuance(args)
               else
                 acquire_via_direct(args)
               end

        @storage.store_certificate(cert)
        cert_without_keyring(cert)
      end

      # Lists identity certificates filtered by certifier and type.
      #
      # @param args [Hash]
      # @return [Hash] { total_certificates:, certificates: [...] }
      def list_certificates(args, originator: nil)
        return @substrate.list_certificates(args, originator: originator) if @substrate

        raise InvalidParameterError.new('certifiers', 'a non-empty Array') unless args[:certifiers].is_a?(Array) && !args[:certifiers].empty?
        raise InvalidParameterError.new('types', 'a non-empty Array') unless args[:types].is_a?(Array) && !args[:types].empty?

        query = {
          certifiers: args[:certifiers],
          types: args[:types],
          limit: args[:limit] || 10,
          offset: args[:offset] || 0
        }
        total = @storage.count_certificates(query)
        certs = @storage.find_certificates(query)
        { total_certificates: total, certificates: certs.map { |c| cert_without_keyring(c) } }
      end

      # Proves select fields of an identity certificate to a verifier.
      #
      # @param args [Hash]
      # @return [Hash] { keyring_for_verifier: { field_name => Array<Integer> } }
      def prove_certificate(args, originator: nil)
        return @substrate.prove_certificate(args, originator: originator) if @substrate

        cert_arg = args[:certificate]
        fields_to_reveal = args[:fields_to_reveal]
        verifier = args[:verifier]

        raise InvalidParameterError.new('certificate', 'a Hash') unless cert_arg.is_a?(Hash)
        raise InvalidParameterError.new('fields_to_reveal', 'a non-empty Array') unless fields_to_reveal.is_a?(Array) && !fields_to_reveal.empty?

        Validators.validate_pub_key_hex!(verifier, 'verifier')

        stored = find_stored_certificate(cert_arg)
        raise WalletError, 'Certificate not found in wallet' unless stored
        raise WalletError, 'Certificate has no keyring' unless stored[:keyring]

        keyring_for_verifier = {}
        fields_to_reveal.each do |field_name|
          key_value = stored[:keyring][field_name] || stored[:keyring][field_name.to_sym]
          raise WalletError, "Keyring entry not found for field '#{field_name}'" unless key_value

          encrypted = encrypt({
                                plaintext: key_value.bytes,
                                protocol_id: [2, 'certificate field encryption'],
                                key_id: "#{cert_arg[:serial_number]} #{field_name}",
                                counterparty: verifier
                              })
          keyring_for_verifier[field_name] = encrypted[:ciphertext]
        end

        { keyring_for_verifier: keyring_for_verifier }
      end

      # Removes a certificate from the wallet.
      #
      # @param args [Hash]
      # @return [Hash] { relinquished: true }
      def relinquish_certificate(args, originator: nil)
        return @substrate.relinquish_certificate(args, originator: originator) if @substrate

        deleted = @storage.delete_certificate(
          type: args[:type],
          serial_number: args[:serial_number],
          certifier: args[:certifier]
        )
        raise WalletError, 'Certificate not found' unless deleted

        { relinquished: true }
      end

      # Discovers certificates issued to a given identity key.
      #
      # @param args [Hash]
      # @return [Hash] { total_certificates:, certificates: [...] }
      def discover_by_identity_key(args, originator: nil)
        return @substrate.discover_by_identity_key(args, originator: originator) if @substrate

        Validators.validate_pub_key_hex!(args[:identity_key], 'identity_key')

        query = { subject: args[:identity_key], limit: args[:limit] || 10, offset: args[:offset] || 0 }
        total = @storage.count_certificates(query)
        certs = @storage.find_certificates(query)
        { total_certificates: total, certificates: certs.map { |c| cert_without_keyring(c) } }
      end

      # Discovers certificates matching specific attribute values.
      #
      # @param args [Hash]
      # @return [Hash] { total_certificates:, certificates: [...] }
      def discover_by_attributes(args, originator: nil)
        return @substrate.discover_by_attributes(args, originator: originator) if @substrate

        raise InvalidParameterError.new('attributes', 'a non-empty Hash') unless args[:attributes].is_a?(Hash) && !args[:attributes].empty?

        query = { attributes: args[:attributes], limit: args[:limit] || 10, offset: args[:offset] || 0 }
        total = @storage.count_certificates(query)
        certs = @storage.find_certificates(query)
        { total_certificates: total, certificates: certs.map { |c| cert_without_keyring(c) } }
      end

      # Maximum ancestor depth to traverse when wiring source transactions.
      ANCESTOR_DEPTH_CAP = 64

      # Rate-limits stale pending recovery to avoid O(n) scans on every auto-fund call.
      STALE_CHECK_INTERVAL = 30

      private

      # --- Identity helpers ---

      def identity_address
        net = @network == 'testnet' ? :testnet : :mainnet
        @key_deriver.root_key.public_key.address(network: net)
      end

      def output_exists?(outpoint)
        @storage.find_outputs({ outpoint: outpoint, include_spent: true, limit: 1, offset: 0 }).any?
      end

      def spendable_pool_eligible?
        @storage.find_spendable_outputs.any? { |o| o.key?(:state) }
      end

      # --- Auto-fund helpers ---

      def auto_fund_and_create(args, caller_outputs)
        release_stale_if_due
        target = caller_outputs.sum { |o| o[:satoshis] || 0 }
        all_spendable = @storage.find_spendable_outputs(basket: 'default')
        available = all_spendable.select do |o|
          (o[:derivation_prefix] && o[:derivation_suffix] && o[:sender_identity_key]) ||
            o[:derivation_type]&.to_s == 'identity'
        end

        selection = auto_fund_select(available, target, caller_outputs.size)
        change_outputs = converge_change(selection, caller_outputs.size)

        no_send = args.dig(:options, :no_send)

        fund_ref = "auto-fund-#{SecureRandom.hex(16)}"
        selected_outpoints = selection[:inputs].map { |u| u[:outpoint] }
        locked = @storage.lock_utxos(selected_outpoints, reference: fund_ref, no_send: no_send)

        if locked.size < selected_outpoints.size
          release_pending_utxos(locked, fund_ref)
          raise InsufficientFundsError.new(
            required: target,
            available: locked.sum { |op| selection[:inputs].find { |u| u[:outpoint] == op }&.fetch(:satoshis, 0) || 0 }
          )
        end

        begin
          tx = build_auto_funded_transaction(selection[:inputs], caller_outputs, change_outputs, args)
          tx.sign_all

          txid = tx.txid_hex
          tx_hex = tx.to_hex

          @storage.store_transaction(txid, tx_hex)

          if no_send
            change_outpoints = store_change_outputs(
              txid, tx, change_outputs, tx_hex,
              state: :pending, pending_reference: fund_ref, no_send: true
            )

            store_action(tx, args, status: 'nosend')
            store_tracked_outputs(txid, tx, caller_outputs)

            @pending[fund_ref] = {
              tx: tx, args: args,
              locked_outpoints: selected_outpoints,
              change_outpoints: change_outpoints
            }
            @pending_by_txid[txid] = fund_ref

            beef_binary = tx.to_beef
            { txid: txid, tx: beef_binary.unpack('C*'), reference: fund_ref, no_send_change: change_outpoints }
          else
            store_action(tx, args, status: 'pending')
            change_outpoints = store_change_outputs(
              txid, tx, change_outputs, tx_hex,
              state: :pending, pending_reference: fund_ref
            )

            store_tracked_outputs(txid, tx, caller_outputs)

            beef_binary = tx.to_beef

            @broadcast_queue.enqueue(
              tx: tx, txid: txid, beef_binary: beef_binary,
              input_outpoints: selected_outpoints,
              change_outpoints: change_outpoints,
              fund_ref: fund_ref,
              accept_delayed_broadcast: args.dig(:options, :accept_delayed_broadcast)
            )
          end
        rescue StandardError
          release_pending_utxos(selected_outpoints, fund_ref)
          raise
        end
      end

      def auto_fund_select(available, target, num_outputs)
        auto_coin_selector.select(
          available: available,
          target_satoshis: target,
          num_outputs: num_outputs
        )
      end

      def converge_change(selection, num_caller_outputs)
        pool_opts = load_pool_opts

        change_outputs = auto_change_generator.generate(
          excess_satoshis: selection[:excess],
          num_existing_outputs: num_caller_outputs,
          **pool_opts
        )

        total_outputs = num_caller_outputs + change_outputs.size
        revised_fee = auto_fee_estimator.estimate(
          p2pkh_inputs: selection[:inputs].size,
          p2pkh_outputs: total_outputs
        )

        fee_delta = revised_fee - selection[:fee]
        return change_outputs if fee_delta.zero?

        adjusted_excess = selection[:excess] - fee_delta
        return [] if adjusted_excess <= 0

        auto_change_generator.generate(
          excess_satoshis: adjusted_excess,
          num_existing_outputs: num_caller_outputs,
          **pool_opts
        )
      end

      def load_pool_opts
        params = @storage.find_setting('change_params')
        return {} unless params

        pool_size = @storage.find_spendable_outputs(basket: 'default').size
        { pool_size: pool_size, change_params: params }
      end

      def build_auto_funded_transaction(selected_utxos, caller_outputs, change_outputs, args)
        version   = args.fetch(:version, 1)
        lock_time = args.fetch(:lock_time, 0)
        tx = BSV::Transaction::Transaction.new(version: version, lock_time: lock_time)

        selected_utxos.each { |utxo| add_auto_funded_input(tx, utxo) }
        caller_outputs.each { |spec| add_output_from_spec(tx, spec) }
        change_outputs.each { |spec| add_output_from_spec(tx, spec) }

        shuffle_outputs(tx) if args.dig(:options, :randomize_outputs) != false && (caller_outputs.size + change_outputs.size) > 1

        tx
      end

      def add_auto_funded_input(tx, utxo)
        txid_hex, index_str = utxo[:outpoint].split('.')
        output_index = index_str.to_i

        input = BSV::Transaction::TransactionInput.new(
          prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex(txid_hex),
          prev_tx_out_index: output_index,
          sequence: 0xFFFFFFFF
        )

        wire_source_from_storage(input, utxo[:outpoint])

        priv = if utxo[:derivation_type]&.to_s == 'identity'
                 @key_deriver.root_key
               else
                 @key_deriver.derive_private_key(
                   ChangeGenerator::BRC29_PROTOCOL_ID,
                   "#{utxo[:derivation_prefix]} #{utxo[:derivation_suffix]}",
                   utxo[:sender_identity_key]
                 )
               end
        input.unlocking_script_template = BSV::Transaction::P2PKH.new(priv)

        tx.add_input(input)
      end

      def add_output_from_spec(tx, spec)
        locking_script = if spec[:locking_script].is_a?(BSV::Script::Script)
                           spec[:locking_script]
                         else
                           BSV::Script::Script.from_hex(spec[:locking_script])
                         end
        output = BSV::Transaction::TransactionOutput.new(
          satoshis: spec[:satoshis],
          locking_script: locking_script
        )
        output.instance_variable_set(:@_spec, spec)
        tx.add_output(output)
      end

      def store_change_outputs(txid, tx, change_specs, tx_hex, state: :spendable, pending_reference: nil, no_send: false)
        outpoints = []
        change_specs.each do |spec|
          actual_idx = tx.outputs.index { |o| o.instance_variable_get(:@_spec).equal?(spec) }
          next unless actual_idx

          entry = change_output_entry(txid, actual_idx, spec, tx_hex, state, pending_reference, no_send)
          @storage.store_output(entry)
          outpoints << "#{txid}.#{actual_idx}"
        end
        outpoints
      end

      def change_output_entry(txid, idx, spec, tx_hex, state, pending_reference, no_send)
        locking_script_hex = spec[:locking_script].is_a?(BSV::Script::Script) ? spec[:locking_script].to_hex : spec[:locking_script]
        entry = {
          outpoint: "#{txid}.#{idx}",
          satoshis: spec[:satoshis],
          locking_script: locking_script_hex,
          basket: 'default',
          tags: [],
          derivation_prefix: spec[:derivation_prefix],
          derivation_suffix: spec[:derivation_suffix],
          sender_identity_key: spec[:sender_identity_key],
          state: state,
          source_tx_hex: tx_hex
        }
        if state == :pending
          entry[:pending_since] = Time.now.utc.iso8601
          entry[:pending_reference] = pending_reference if pending_reference
          entry[:no_send] = true if no_send
        end
        entry
      end

      def auto_fee_estimator
        @auto_fee_estimator ||= @injected_fee_estimator || FeeEstimator.new
      end

      def auto_coin_selector
        @auto_coin_selector ||= @injected_coin_selector || CoinSelector.new(fee_estimator: auto_fee_estimator)
      end

      def auto_change_generator
        @auto_change_generator ||= @injected_change_generator || ChangeGenerator.new(
          key_deriver: @key_deriver,
          fee_estimator: auto_fee_estimator
        )
      end

      # --- Validation ---

      def validate_broadcast_configuration!(args)
        no_send = args.dig(:options, :no_send)
        return if no_send
        return if broadcast_enabled?

        raise WalletError,
              'create_action requires a broadcaster for on-chain broadcast. ' \
              'Pass broadcaster: BSV::Network::ARC.default to Client.new, ' \
              'or options: { no_send: true } to build a transaction without broadcasting.'
      end

      def validate_create_action!(args)
        Validators.validate_description!(args[:description])
        inputs_present = args[:inputs] && !args[:inputs].empty?
        outputs_present = args[:outputs] && !args[:outputs].empty?
        send_with_present = args.dig(:options, :send_with) && !Array(args.dig(:options, :send_with)).empty?
        unless inputs_present || outputs_present || send_with_present
          raise InvalidParameterError.new('inputs/outputs', 'at least one input or output')
        end

        validate_action_inputs!(args[:inputs]) if args[:inputs]
        validate_action_outputs!(args[:outputs]) if args[:outputs]
        args[:labels]&.each { |l| Validators.validate_label!(l) }
      end

      def validate_action_inputs!(inputs)
        inputs.each do |input|
          Validators.validate_outpoint!(input[:outpoint])
          Validators.validate_description!(input[:input_description], 'input_description')
          unless input[:unlocking_script] || input[:unlocking_script_length]
            raise InvalidParameterError.new('unlocking_script',
                                            'provided, or unlocking_script_length must be set')
          end
        end
      end

      def validate_action_outputs!(outputs)
        outputs.each do |output|
          Validators.validate_hex_string!(output[:locking_script], 'locking_script')
          Validators.validate_satoshis!(output[:satoshis])
          Validators.validate_description!(output[:output_description], 'output_description')
          Validators.validate_basket!(output[:basket]) if output[:basket]
          output[:tags]&.each { |t| Validators.validate_tag!(t) }
        end
      end

      def validate_list_actions!(args)
        raise InvalidParameterError.new('labels', 'a non-empty Array') unless args[:labels].is_a?(Array) && !args[:labels].empty?

        args[:labels].each { |l| Validators.validate_label!(l) }
      end

      def validate_list_outputs!(args)
        Validators.validate_basket!(args[:basket])
        args[:tags]&.each { |t| Validators.validate_tag!(t) }
      end

      def validate_internalize_action!(args)
        raise InvalidParameterError.new('tx', 'a byte array') unless args[:tx].is_a?(Array)
        raise InvalidParameterError.new('outputs', 'a non-empty Array') unless args[:outputs].is_a?(Array) && !args[:outputs].empty?

        Validators.validate_description!(args[:description])
        args[:labels]&.each { |l| Validators.validate_label!(l) }
      end

      # --- Transaction building ---

      def parse_input_beef(input_beef)
        return unless input_beef

        BSV::Transaction::Beef.from_binary(input_beef.pack('C*'))
      end

      def build_transaction(args, beef)
        version = args.fetch(:version, 1)
        lock_time = args.fetch(:lock_time, 0)
        tx = BSV::Transaction::Transaction.new(version: version, lock_time: lock_time)

        build_inputs(tx, args[:inputs], beef) if args[:inputs]
        build_outputs(tx, args[:outputs]) if args[:outputs]

        shuffle_outputs(tx) if args[:inputs] && args[:outputs] && args.dig(:options, :randomize_outputs) != false

        tx
      end

      def build_inputs(tx, inputs, beef)
        inputs.each do |spec|
          txid_hex, index_str = spec[:outpoint].split('.')
          output_index = index_str.to_i
          seq = spec[:sequence_number] || 0xFFFFFFFF

          input = BSV::Transaction::TransactionInput.new(
            prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex(txid_hex),
            prev_tx_out_index: output_index,
            sequence: seq
          )

          wire_source(input, txid_hex, output_index, beef) if beef
          wire_source_from_storage(input, spec[:outpoint]) if input.source_satoshis.nil? || input.source_locking_script.nil?

          case spec[:unlocking_script]
          when BSV::Transaction::UnlockingScriptTemplate
            input.unlocking_script_template = spec[:unlocking_script]
          when String
            input.unlocking_script = BSV::Script::Script.from_hex(spec[:unlocking_script])
          when nil then nil
          else
            raise InvalidParameterError.new('unlocking_script', 'a hex String or UnlockingScriptTemplate')
          end

          tx.add_input(input)
        end
      end

      def wire_source(input, txid_hex, output_index, beef)
        txid_display = [txid_hex].pack('H*')
        source_beef_tx = beef.transactions.find { |bt| bt.transaction&.txid == txid_display }
        return unless source_beef_tx

        source_tx = source_beef_tx.transaction
        input.source_transaction = source_tx
        return unless source_tx.outputs[output_index]

        input.source_satoshis = source_tx.outputs[output_index].satoshis
        input.source_locking_script = source_tx.outputs[output_index].locking_script
      end

      def wire_source_from_storage(input, outpoint)
        results = @storage.find_outputs({ outpoint: outpoint, include_spent: true, limit: 1 })
        stored = results.first
        return unless stored

        input.source_satoshis = stored[:satoshis]
        input.source_locking_script = BSV::Script::Script.from_hex(stored[:locking_script])

        return unless stored[:source_tx_hex]

        source_tx = BSV::Transaction::Transaction.from_hex(stored[:source_tx_hex])
        txid_hex = outpoint.split('.').first
        proof = @proof_store.resolve_proof(txid_hex)
        source_tx.merkle_path = proof if proof

        wire_source_tx_ancestors(source_tx) unless source_tx.merkle_path

        input.source_transaction = source_tx
      end

      def wire_source_tx_ancestors(tx, visited: nil, depth: 0)
        return if depth >= ANCESTOR_DEPTH_CAP

        visited ||= Set.new
        tx_txid = tx.txid_hex
        return if visited.include?(tx_txid)

        visited.add(tx_txid)

        tx.inputs.each do |inp|
          next if inp.source_transaction

          ancestor_txid_hex = inp.prev_tx_id.reverse.unpack1('H*')
          next if visited.include?(ancestor_txid_hex)

          tx_hex = @storage.find_transaction(ancestor_txid_hex)
          next unless tx_hex

          ancestor_tx = BSV::Transaction::Transaction.from_hex(tx_hex)
          proof = @proof_store.resolve_proof(ancestor_txid_hex)
          ancestor_tx.merkle_path = proof if proof
          wire_source_tx_ancestors(ancestor_tx, visited: visited, depth: depth + 1) unless ancestor_tx.merkle_path
          inp.source_transaction = ancestor_tx
        end
      end

      def build_outputs(tx, outputs)
        outputs.each do |spec|
          output = BSV::Transaction::TransactionOutput.new(
            satoshis: spec[:satoshis],
            locking_script: BSV::Script::Script.from_hex(spec[:locking_script])
          )
          output.instance_variable_set(:@_spec, spec)
          tx.add_output(output)
        end
      end

      def shuffle_outputs(tx)
        shuffled = tx.outputs.shuffle
        tx.outputs.clear
        shuffled.each { |o| tx.add_output(o) }
      end

      def needs_signing?(inputs)
        return false unless inputs

        inputs.any? { |i| i[:unlocking_script_length] && !i[:unlocking_script] }
      end

      # --- Finalisation ---

      def create_signable(tx, args, beef)
        reference = Base64.strict_encode64(SecureRandom.random_bytes(32))
        @pending[reference] = { tx: tx, args: args, beef: beef }
        tx_bytes = tx.to_binary
        { signable_transaction: { tx: tx_bytes.unpack('C*'), reference: reference } }
      end

      def release_stale_if_due
        now = Time.now.utc
        return if @last_stale_check && (now - @last_stale_check) < STALE_CHECK_INTERVAL

        @storage.release_stale_pending!
        @last_stale_check = now
      end

      def release_pending_utxos(outpoints, ref)
        Array(outpoints).each do |op|
          outputs = @storage.find_outputs({ outpoint: op, include_spent: true, limit: 1, offset: 0 })
          next if outputs.empty?
          next unless outputs.first[:pending_reference] == ref

          @storage.update_output_state(op, :spendable)
        end
      end

      def rollback_pending_action(input_outpoints, change_outpoints, txid, ref, action_status: nil)
        release_pending_utxos(input_outpoints, ref)
        Array(change_outpoints).each { |op| @storage.delete_output(op) }
        @storage.update_action_status(txid, action_status) if txid && action_status
      end

      def broadcast_and_promote(tx, txid, input_outpoints, change_outpoints, fund_ref, beef_binary)
        @broadcast_queue.enqueue(
          tx: tx, txid: txid, beef_binary: beef_binary,
          input_outpoints: input_outpoints,
          change_outpoints: change_outpoints,
          fund_ref: fund_ref,
          accept_delayed_broadcast: false
        )
      end

      def broadcast_send_with(txids)
        txids.map { |txid| broadcast_single_no_send(txid) }
      end

      def broadcast_single_no_send(txid)
        fund_ref = @pending_by_txid[txid]
        return { txid: txid, status: 'failed', error: 'Transaction not found in pending no_send store' } unless fund_ref

        pending_entry = @pending[fund_ref]
        unless pending_entry
          @pending_by_txid.delete(txid)
          return { txid: txid, status: 'failed', error: 'Pending entry expired or already processed' }
        end

        tx = pending_entry[:tx]
        unless tx
          tx_hex = @storage.find_transaction(txid)
          return { txid: txid, status: 'failed', error: 'Transaction not found' } unless tx_hex

          tx = BSV::Transaction::Transaction.from_hex(tx_hex)
        end
        promote_no_send(tx, txid, fund_ref, pending_entry)
      rescue StandardError => e
        { txid: txid, status: 'failed', error: e.message }
      end

      def promote_no_send(tx, txid, fund_ref, pending_entry)
        begin
          @broadcaster.broadcast(tx)
        rescue StandardError => e
          rollback_pending_action(
            pending_entry[:locked_outpoints],
            pending_entry[:change_outpoints],
            txid,
            fund_ref,
            action_status: 'failed'
          )
          @pending.delete(fund_ref)
          @pending_by_txid.delete(txid)
          return { txid: txid, status: 'failed', error: e.message }
        end

        pending_entry[:locked_outpoints].each { |op| @storage.update_output_state(op, :spent) }
        pending_entry[:change_outpoints].each { |op| @storage.update_output_state(op, :spendable) }
        @storage.update_action_status(txid, 'unproven')
        @pending.delete(fund_ref)
        @pending_by_txid.delete(txid)

        { txid: txid, status: 'unproven' }
      end

      def broadcast_status_for(error)
        BroadcastQueue.status_for_error(error)
      end

      def finalize_action(tx, args)
        tx.sign_all if tx.inputs.any?(&:unlocking_script_template)
        txid = tx.txid_hex

        no_send = args.dig(:options, :no_send)
        delayed = args.dig(:options, :accept_delayed_broadcast)

        status = no_send ? 'nosend' : 'pending'

        @storage.store_transaction(txid, tx.to_hex)
        store_action(tx, args, status: status)
        store_tracked_outputs(txid, tx, args[:outputs])

        beef_binary = tx.to_beef
        result = { txid: txid, tx: beef_binary.unpack('C*') }

        if no_send
          result[:no_send_change] = []
        else
          result.merge!(
            @broadcast_queue.enqueue(
              tx: tx, txid: txid, beef_binary: beef_binary,
              input_outpoints: nil, change_outpoints: nil, fund_ref: nil,
              accept_delayed_broadcast: delayed
            )
          )
        end

        result
      end

      def apply_spends(tx, spends)
        spends.each do |index, spend|
          idx = index.is_a?(String) ? index.to_i : index
          raise WalletError, "Input index #{idx} out of range" unless tx.inputs[idx]

          tx.inputs[idx].unlocking_script = BSV::Script::Script.from_hex(spend[:unlocking_script])
          tx.inputs[idx].instance_variable_set(:@sequence, spend[:sequence_number]) if spend[:sequence_number]
        end
      end

      # --- Storage helpers ---

      def store_action(tx, args, status: 'completed')
        @storage.store_action({
                                txid: tx.txid_hex,
                                status: status,
                                description: args[:description],
                                labels: args[:labels] || [],
                                is_outgoing: true,
                                satoshis: tx.total_output_satoshis,
                                version: tx.version,
                                lock_time: tx.lock_time,
                                created_at: Time.now.utc.iso8601
                              })
      end

      def store_tracked_outputs(txid, tx, output_specs)
        return unless output_specs

        tx_hex = tx.to_hex

        output_specs.each do |spec|
          next unless spec[:basket]

          actual_idx = tx.outputs.index { |o| o.instance_variable_get(:@_spec).equal?(spec) }
          next unless actual_idx

          @storage.store_output({
                                  outpoint: "#{txid}.#{actual_idx}",
                                  satoshis: spec[:satoshis],
                                  locking_script: spec[:locking_script],
                                  basket: spec[:basket],
                                  tags: spec[:tags] || [],
                                  custom_instructions: spec[:custom_instructions],
                                  spendable: true,
                                  source_tx_hex: tx_hex,
                                  derivation_prefix: spec[:derivation_prefix],
                                  derivation_suffix: spec[:derivation_suffix],
                                  sender_identity_key: spec[:sender_identity_key]
                                })
        end
      end

      def build_action_query(args)
        {
          labels: args[:labels],
          label_query_mode: args[:label_query_mode] || 'any',
          limit: args[:limit] || 10,
          offset: args[:offset] || 0
        }
      end

      def build_output_query(args)
        query = {
          basket: args[:basket],
          limit: args[:limit] || 10,
          offset: args[:offset] || 0
        }
        query[:tags] = args[:tags] if args[:tags]
        query[:tag_query_mode] = args[:tag_query_mode] if args[:tag_query_mode]
        query
      end

      # --- Include-flag stripping ---

      def strip_action_fields(actions, args)
        actions.map do |action|
          a = action.dup
          a.delete(:labels) unless args[:include_labels] == true
          a.delete(:inputs) unless args[:include_inputs] == true

          if a.key?(:inputs)
            strip_src = args[:include_input_source_locking_scripts] != true
            strip_unlock = args[:include_input_unlocking_scripts] != true
            if strip_src || strip_unlock
              a[:inputs] = a[:inputs].map do |i|
                d = i.dup
                d.delete(:source_locking_script) if strip_src
                d.delete(:unlocking_script) if strip_unlock
                d
              end
            end
          end

          a.delete(:outputs) unless args[:include_outputs] == true

          if a.key?(:outputs) && args[:include_output_locking_scripts] != true
            a[:outputs] = a[:outputs].map { |o| o.dup.tap { |h| h.delete(:locking_script) } }
          end

          a
        end
      end

      def strip_output_fields(outputs, args)
        outputs.map do |output|
          o = output.dup
          o.delete(:tags) unless args[:include_tags] == true
          o.delete(:labels) unless args[:include_labels] == true
          o.delete(:custom_instructions) unless args[:include_custom_instructions] == true
          o
        end
      end

      # --- Internalize helpers ---

      def store_proofs_from_beef(beef)
        beef.transactions.each do |beef_tx|
          next unless beef_tx.transaction

          txid_hex = beef_tx.transaction.txid_hex
          @storage.store_transaction(txid_hex, beef_tx.transaction.to_hex)
          @proof_store.store_proof(txid_hex, beef_tx.transaction.merkle_path) if beef_tx.transaction.merkle_path
        end
      end

      def extract_subject_transaction(beef)
        return find_by_subject_txid(beef) if beef.subject_txid

        last_beef_tx = beef.transactions.reverse.find(&:transaction)
        raise WalletError, 'No transaction found in BEEF' unless last_beef_tx

        last_beef_tx.transaction
      end

      def find_by_subject_txid(beef)
        beef.find_atomic_transaction(beef.subject_txid) ||
          raise(WalletError, 'Subject transaction not found in BEEF')
      end

      def process_internalize_outputs(tx, output_specs)
        txid = tx.txid_hex
        tx_hex = tx.to_hex

        output_specs.each do |spec|
          output_index = spec[:output_index]
          tx_output = tx.outputs[output_index]
          raise WalletError, "Output index #{output_index} not found in transaction" unless tx_output

          case spec[:protocol]
          when 'wallet payment'
            internalize_payment(txid, output_index, tx_output, spec[:payment_remittance], tx_hex)
          when 'basket insertion'
            internalize_basket(txid, output_index, tx_output, spec[:insertion_remittance], tx_hex)
          else
            raise InvalidParameterError.new('protocol', '"wallet payment" or "basket insertion"')
          end
        end
      end

      def internalize_payment(txid, output_index, tx_output, remittance, tx_hex = nil)
        unless remittance
          raise InvalidParameterError.new('payment_remittance',
                                          'present for wallet payment protocol')
        end

        sender_key = remittance[:sender_identity_key]
        prefix = remittance[:derivation_prefix]
        suffix = remittance[:derivation_suffix]

        derived_pub = @key_deriver.derive_public_key(
          ChangeGenerator::BRC29_PROTOCOL_ID,
          "#{prefix} #{suffix}",
          sender_key,
          for_self: true
        )
        expected_script = BSV::Script::Script.p2pkh_lock(derived_pub.hash160)

        raise WalletError, 'Output script does not match derived payment key' unless tx_output.locking_script.to_binary == expected_script.to_binary

        @storage.store_output({
                                outpoint: "#{txid}.#{output_index}",
                                satoshis: tx_output.satoshis,
                                locking_script: tx_output.locking_script.to_hex,
                                basket: 'default',
                                spendable: true,
                                sender_identity_key: sender_key,
                                derivation_prefix: prefix,
                                derivation_suffix: suffix,
                                source_tx_hex: tx_hex
                              })
      end

      def internalize_basket(txid, output_index, tx_output, remittance, tx_hex = nil)
        unless remittance
          raise InvalidParameterError.new('insertion_remittance',
                                          'present for basket insertion protocol')
        end

        Validators.validate_basket!(remittance[:basket])

        @storage.store_output({
                                outpoint: "#{txid}.#{output_index}",
                                satoshis: tx_output.satoshis,
                                locking_script: tx_output.locking_script.to_hex,
                                basket: remittance[:basket],
                                tags: remittance[:tags] || [],
                                custom_instructions: remittance[:custom_instructions],
                                spendable: true,
                                source_tx_hex: tx_hex
                              })
      end

      # --- Certificate helpers ---

      def validate_acquire_certificate!(args)
        raise InvalidParameterError.new('type', 'a String') unless args[:type].is_a?(String)

        Validators.validate_pub_key_hex!(args[:certifier], 'certifier')
        raise InvalidParameterError.new('fields', 'a Hash') unless args[:fields].is_a?(Hash)

        protocol = args[:acquisition_protocol]
        raise InvalidParameterError.new('acquisition_protocol', '"direct" or "issuance"') unless %w[direct issuance].include?(protocol)

        if protocol == 'direct'
          raise InvalidParameterError.new('serial_number', 'present for direct acquisition') unless args[:serial_number]
          raise InvalidParameterError.new('revocation_outpoint', 'present for direct acquisition') unless args[:revocation_outpoint]
          raise InvalidParameterError.new('signature', 'present for direct acquisition') unless args[:signature]
          raise InvalidParameterError.new('keyring_for_subject', 'a Hash for direct acquisition') unless args[:keyring_for_subject].is_a?(Hash)
        elsif protocol == 'issuance'
          raise InvalidParameterError.new('certifier_url', 'present for issuance acquisition') unless args[:certifier_url].is_a?(String)
        end
      end

      def acquire_via_direct(args)
        cert = {
          type: args[:type],
          subject: @key_deriver.identity_key,
          serial_number: args[:serial_number],
          certifier: args[:certifier],
          revocation_outpoint: args[:revocation_outpoint],
          signature: args[:signature],
          fields: args[:fields],
          keyring: args[:keyring_for_subject]
        }

        CertificateSignature.verify!(cert)

        cert
      end

      def acquire_via_issuance(args)
        response = auth_fetch_client.fetch(
          args[:certifier_url],
          method: 'POST',
          headers: { 'content-type' => 'application/json' },
          body: JSON.generate({
                                type: args[:type],
                                subject: @key_deriver.identity_key,
                                certifier: args[:certifier],
                                fields: args[:fields]
                              })
        )

        raise WalletError, "Certificate issuance failed: HTTP #{response.status}" unless (200..299).cover?(response.status)

        body = JSON.parse(response.body)

        cert = {
          type: body['type'] || args[:type],
          subject: @key_deriver.identity_key,
          serial_number: body['serialNumber'],
          certifier: args[:certifier],
          revocation_outpoint: body['revocationOutpoint'],
          signature: body['signature'],
          fields: body['fields'] || args[:fields],
          keyring: body['keyringForSubject']
        }

        CertificateSignature.verify!(cert)

        cert
      rescue JSON::ParserError
        raise WalletError, 'Certificate issuance failed: invalid JSON response'
      end

      def auth_fetch_client
        @auth_fetch_client ||= BSV::Auth::AuthFetch.new(wallet: self)
      end

      def execute_http(uri, request)
        if @http_client
          @http_client.request(uri, request)
        else
          Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
            http.request(request)
          end
        end
      end

      def find_stored_certificate(cert_arg)
        results = @storage.find_certificates({
                                               certifiers: [cert_arg[:certifier]],
                                               types: [cert_arg[:type]],
                                               limit: 10_000
                                             })
        results.find { |c| c[:serial_number] == cert_arg[:serial_number] }
      end

      def cert_without_keyring(cert)
        result = cert.dup
        result.delete(:keyring)
        result
      end
    end
  end
end
