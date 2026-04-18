# frozen_string_literal: true

require 'securerandom'
require 'base64'
require 'net/http'
require 'json'
require 'set'
require 'uri'

module BSV
  module Wallet
    # BRC-100 transaction operations for the wallet interface.
    #
    # Implements the 7 transaction-related BRC-100 methods on top of
    # {ProtoWallet}: create_action, sign_action, abort_action, list_actions,
    # list_outputs, relinquish_output, and internalize_action.
    #
    # Transactions are built using the SDK's {BSV::Transaction::Transaction}
    # class. Completed actions and tracked outputs are persisted via a
    # {StorageAdapter} (defaults to {MemoryStore}).
    #
    # @example Create a simple transaction
    #   client = BSV::Wallet::WalletClient.new(private_key)
    #   result = client.create_action({
    #     description: 'Pay invoice',
    #     outputs: [{ locking_script: '76a914...88ac', satoshis: 1000,
    #                 output_description: 'Payment' }]
    #   })
    class WalletClient < ProtoWallet
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
      # @param broadcaster [#broadcast, nil] optional broadcaster; any object responding to #broadcast(tx)
      # @param broadcast_queue [BroadcastQueue, nil] optional broadcast queue; defaults to InlineQueue
      # @param substrate [Interface, nil] optional remote wallet substrate; when set, all Interface
      #   methods delegate to the substrate instead of using local storage and key derivation.
      #   Accepts any object implementing {Interface} (e.g. {Substrates::HTTPWalletJSON},
      #   {Substrates::WalletWireTransceiver}).
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
        super(key)
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
      #
      # Delegates to the broadcast queue so that queue-embedded broadcasters
      # (e.g. +SolidQueueAdapter.new(broadcaster: arc)+) are recognised even
      # when no +broadcaster:+ was passed directly to +WalletClient+.
      def broadcast_enabled?
        @broadcast_queue.broadcast_enabled?
      end

      # --- Transaction Operations ---

      # Creates a new Bitcoin transaction.
      #
      # When the +:auto_fund+ option is +true+ (and +:outputs+ are provided
      # but no +:inputs+), the wallet automatically selects UTXOs from the
      # default basket, estimates fees, generates change, and returns a
      # complete signed transaction (auto-fund mode).
      #
      # Without +:auto_fund+, if all inputs carry unlocking_script values,
      # the transaction is finalised immediately and returned with :txid and
      # :tx (BEEF bytes). If any input specifies only unlocking_script_length,
      # the transaction is held pending and returned as a signable_transaction
      # for external signing via {#sign_action}.
      #
      # @param args [Hash] transaction parameters
      # @option args [Boolean] :auto_fund when +true+, automatically selects
      #   UTXOs and generates change; requires +:outputs+ and no +:inputs+
      # @param _originator [String, nil] FQDN of the originating application
      # @return [Hash] finalised result or signable_transaction
      def create_action(args, originator: nil)
        return @substrate.create_action(args, originator: originator) if @substrate

        validate_create_action!(args)
        validate_broadcast_configuration!(args)

        send_with_txids = Array(args.dig(:options, :send_with))

        outputs = args[:outputs] || []
        inputs  = args[:inputs]

        # When send_with is provided but no new transaction body is specified,
        # broadcast only the batched no_send transactions.
        if !send_with_txids.empty? && outputs.empty? && (inputs.nil? || inputs.empty?)
          raise WalletError, 'A broadcaster is required to use send_with' unless broadcast_enabled?

          return { send_with_results: broadcast_send_with(send_with_txids) }
        end

        if (inputs.nil? || inputs.empty?) && !outputs.empty? && (args[:auto_fund] || spendable_pool_eligible?)
          result = auto_fund_and_create(args, outputs)
          # If send_with was also specified, batch-broadcast those alongside the
          # current transaction's implicit broadcast.
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
      # @option args [Hash] :spends map of input index (Integer or String) to
      #   { unlocking_script: hex, sequence_number: Integer }
      # @option args [String] :reference base64 reference from create_action
      # @param _originator [String, nil] FQDN of the originating application
      # @return [Hash] with :txid and :tx (BEEF bytes)
      def sign_action(args, originator: nil)
        return @substrate.sign_action(args, originator: originator) if @substrate

        reference = args[:reference]
        pending = @pending[reference]
        raise WalletError, 'Transaction not found for the given reference' unless pending

        tx = pending[:tx]
        apply_spends(tx, args[:spends])
        @pending.delete(reference)

        # Merge sign_action's own options over the original create_action args so
        # callers can supply accept_delayed_broadcast at sign time.
        merged_args = if args[:options]
                        pending[:args].merge(options: (pending[:args][:options] || {}).merge(args[:options]))
                      else
                        pending[:args]
                      end

        # Re-validate broadcast configuration on merged args — options may have
        # been flipped between create_action and sign_action (e.g. no_send toggled).
        validate_broadcast_configuration!(merged_args)

        finalize_action(tx, merged_args)
      end

      # Aborts a pending signable transaction.
      #
      # If the pending entry holds UTXO references (stored by auto-fund), any
      # outputs locked as +:pending+ with that reference are released back to
      # +:spendable+ so they become eligible for future coin selection.
      #
      # @param args [Hash]
      # @option args [String] :reference base64 reference to abort
      # @param _originator [String, nil] FQDN of the originating application
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
      # @option args [String] :label_query_mode 'any' (default) or 'all'
      # @option args [Integer] :limit max results (default 10)
      # @option args [Integer] :offset results to skip (default 0)
      # @param _originator [String, nil] FQDN of the originating application
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
      # @option args [Array<String>] :tags optional tag filter
      # @option args [String] :tag_query_mode 'any' (default) or 'all'
      # @option args [Integer] :limit max results (default 10)
      # @option args [Integer] :offset results to skip (default 0)
      # @param _originator [String, nil] FQDN of the originating application
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
      # @param _originator [String, nil] FQDN of the originating application
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
      # Parses the BEEF, locates the subject transaction, processes each
      # specified output according to its protocol (wallet payment or basket
      # insertion), and stores the action.
      #
      # @param args [Hash]
      # @option args [Array<Integer>] :tx Atomic BEEF-formatted transaction as byte array
      # @option args [Array<Hash>] :outputs output metadata
      # @option args [String] :description 5-50 char description
      # @option args [Array<String>] :labels optional labels
      # @param _originator [String, nil] FQDN of the originating application
      # @return [Hash] { accepted: true }
      def internalize_action(args, originator: nil)
        return @substrate.internalize_action(args, originator: originator) if @substrate

        validate_internalize_action!(args)
        beef_binary = args[:tx].pack('C*')
        beef = BSV::Transaction::Beef.from_binary(beef_binary)

        # F8.14: verify the BEEF bundle before trusting its contents.
        # Fall back to structural validation — no chain tracker available locally.
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
      # Requires a substrate — raises {UnsupportedActionError} when called on a
      # local wallet with no substrate configured.
      #
      # @param _args [Hash] unused (empty hash)
      # @return [Hash] { height: Integer }
      def get_height(args = {}, originator: nil)
        return @substrate.get_height(args, originator: originator) if @substrate

        raise UnsupportedActionError, 'get_height requires a remote substrate'
      end

      # Returns the block header at the given height.
      #
      # Requires a substrate — raises {UnsupportedActionError} when called on a
      # local wallet with no substrate configured.
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
      # @param _args [Hash] unused (empty hash)
      # @return [Hash] { network: String } 'mainnet' or 'testnet'
      def get_network(args = {}, originator: nil)
        return @substrate.get_network(args, originator: originator) if @substrate

        { network: @network }
      end

      # Returns the wallet version string.
      #
      # @param _args [Hash] unused (empty hash)
      # @return [Hash] { version: String } in vendor-major.minor.patch format
      def get_version(args = {}, originator: nil)
        return @substrate.get_version(args, originator: originator) if @substrate

        { version: "bsv-wallet-#{BSV::Wallet::VERSION}" }
      end

      # Raises {UnsupportedActionError}.
      #
      # UTXO synchronisation previously required a ChainProvider. That class has
      # been removed. Use a remote substrate or a custom integration to discover
      # UTXOs and import them via +store_output+ directly.
      def sync_utxos
        raise UnsupportedActionError, 'sync_utxos requires a remote substrate or custom integration'
      end

      # --- UTXO Pool & Settings ---

      # Returns the total spendable satoshis across all baskets (or a named basket).
      #
      # Includes every output in +:spendable+ state — regardless of whether the
      # wallet holds the signing key. This answers "how much does this wallet hold?",
      # not "how much can it auto-spend?". Use {#spendable_balance} for the latter.
      #
      # @param basket [String, nil] the basket to total, or +nil+ for all baskets
      # @return [Integer] sum of all spendable output values
      def balance(basket: nil)
        @storage.find_spendable_outputs(basket: basket).sum { |o| o[:satoshis].to_i }
      end

      # Returns the total satoshis of outputs the wallet can automatically spend.
      #
      # Only outputs carrying full BRC-29 derivation metadata
      # (+derivation_prefix+, +derivation_suffix+, +sender_identity_key+) are
      # counted — these are the outputs the wallet can sign without external input.
      # Basket-only outputs (e.g. tokens without derivation data) contribute to
      # {#balance} but not here.
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
      # When set, the auto-fund path will use these parameters to decide how
      # many change outputs to produce:
      #   - If the pool is below +:count+, more change outputs are generated
      #     (up to +max_outputs+) to build up the UTXO pool.
      #   - If the pool is at or above +:count+, fewer outputs are generated
      #     (1-2) to avoid fragmenting the pool unnecessarily.
      #
      # @param count [Integer] desired number of spendable UTXOs in 'default' basket
      # @param satoshis [Integer] desired average value per UTXO in satoshis
      # @raise [InvalidParameterError] if +count+ or +satoshis+ are not positive integers
      def set_wallet_change_params(count:, satoshis:)
        raise InvalidParameterError.new('count', 'a positive Integer') unless count.is_a?(Integer) && count.positive?
        raise InvalidParameterError.new('satoshis', 'a positive Integer') unless satoshis.is_a?(Integer) && satoshis.positive?

        @storage.store_setting('change_params', { count: count, satoshis: satoshis })
      end

      # Creates a UTXO pool for high-frequency transaction pre-allocation.
      #
      # The pool maintains a basket of pre-funded outputs (e.g. +'pool:doom'+)
      # that can be acquired and released without the overhead of full coin
      # selection. A background {ReplenishmentWorker} keeps the pool at
      # target capacity.
      #
      # The caller is responsible for calling +pool.shutdown+ when the pool
      # is no longer needed to stop the background worker.
      #
      # @param name [String] pool identifier (basket will be +"pool:<name>"+)
      # @param target_count [Integer] desired number of UTXOs (default 20)
      # @param target_satoshis [Integer] desired satoshis per UTXO (default 10_000)
      # @param low_water_mark [Float] replenishment trigger as a fraction of
      #   +target_count+ (0.0-1.0, default 0.5); threshold is
      #   <tt>(target_count * low_water_mark).ceil</tt>
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
      # For local wallets with a private key, this is always true.
      #
      # @param _args [Hash] unused (empty hash)
      # @return [Hash] { authenticated: Boolean }
      def is_authenticated(args = {}, originator: nil)
        return @substrate.is_authenticated(args, originator: originator) if @substrate

        { authenticated: true }
      end

      # Waits until the user is authenticated.
      # For local wallets, returns immediately.
      #
      # @param _args [Hash] unused (empty hash)
      # @return [Hash] { authenticated: true }
      def wait_for_authentication(args = {}, originator: nil)
        return @substrate.wait_for_authentication(args, originator: originator) if @substrate

        { authenticated: true }
      end

      # --- Identity and Certificate Management ---

      # Acquires an identity certificate via direct storage.
      #
      # The 'issuance' protocol (which requires HTTP to a certifier URL) is
      # not yet supported and raises {UnsupportedActionError}.
      #
      # @param args [Hash]
      # @option args [String] :type certificate type (base64)
      # @option args [String] :certifier certifier public key hex
      # @option args [String] :acquisition_protocol 'direct' or 'issuance'
      # @option args [Hash] :fields certificate fields (field_name => value)
      # @option args [String] :serial_number serial number (required for direct)
      # @option args [String] :revocation_outpoint outpoint string (required for direct)
      # @option args [String] :signature certifier signature hex (required for direct)
      # @option args [String] :keyring_revealer pubkey hex or 'certifier' (required for direct)
      # @option args [Hash] :keyring_for_subject field_name => base64 key (required for direct)
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
      # @option args [Array<String>] :certifiers certifier public keys
      # @option args [Array<String>] :types certificate types
      # @option args [Integer] :limit max results (default 10)
      # @option args [Integer] :offset number to skip (default 0)
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
      # Encrypts each requested field's keyring entry for the verifier using
      # protocol-derived encryption (BRC-2), allowing the verifier to decrypt
      # only the revealed fields.
      #
      # @param args [Hash]
      # @option args [Hash] :certificate the certificate to prove
      # @option args [Array<String>] :fields_to_reveal field names to reveal
      # @option args [String] :verifier verifier public key hex
      # @return [Hash] { keyring_for_verifier: { field_name => Array<Integer> } }
      def prove_certificate(args, originator: nil)
        return @substrate.prove_certificate(args, originator: originator) if @substrate

        cert_arg = args[:certificate]
        fields_to_reveal = args[:fields_to_reveal]
        verifier = args[:verifier]

        raise InvalidParameterError.new('certificate', 'a Hash') unless cert_arg.is_a?(Hash)
        raise InvalidParameterError.new('fields_to_reveal', 'a non-empty Array') unless fields_to_reveal.is_a?(Array) && !fields_to_reveal.empty?

        Validators.validate_pub_key_hex!(verifier, 'verifier')

        # Look up the full certificate (with keyring) from storage
        stored = find_stored_certificate(cert_arg)
        raise WalletError, 'Certificate not found in wallet' unless stored
        raise WalletError, 'Certificate has no keyring' unless stored[:keyring]

        keyring_for_verifier = {}
        fields_to_reveal.each do |field_name|
          key_value = stored[:keyring][field_name] || stored[:keyring][field_name.to_sym]
          raise WalletError, "Keyring entry not found for field '#{field_name}'" unless key_value

          # Encrypt the keyring entry for the verifier
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
      # @option args [String] :type certificate type
      # @option args [String] :serial_number serial number
      # @option args [String] :certifier certifier public key hex
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
      # For a local wallet, searches stored certificates where the subject
      # matches the given identity key.
      #
      # @param args [Hash]
      # @option args [String] :identity_key public key hex to search
      # @option args [Integer] :limit max results (default 10)
      # @option args [Integer] :offset number to skip (default 0)
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
      # Searches stored certificates where field values match the given
      # attributes. Only searches certificates belonging to this wallet.
      #
      # @param args [Hash]
      # @option args [Hash] :attributes field_name => value pairs to match
      # @option args [Integer] :limit max results (default 10)
      # @option args [Integer] :offset number to skip (default 0)
      # @return [Hash] { total_certificates:, certificates: [...] }
      def discover_by_attributes(args, originator: nil)
        return @substrate.discover_by_attributes(args, originator: originator) if @substrate

        raise InvalidParameterError.new('attributes', 'a non-empty Hash') unless args[:attributes].is_a?(Hash) && !args[:attributes].empty?

        query = { attributes: args[:attributes], limit: args[:limit] || 10, offset: args[:offset] || 0 }
        total = @storage.count_certificates(query)
        certs = @storage.find_certificates(query)
        { total_certificates: total, certificates: certs.map { |c| cert_without_keyring(c) } }
      end

      # --- ProtoWallet crypto method overrides for substrate delegation ---
      #
      # When a substrate is configured, these methods delegate to it rather than
      # performing local key derivation and cryptographic operations.

      def get_public_key(args, originator: nil)
        return @substrate.get_public_key(args, originator: originator) if @substrate

        super
      end

      def reveal_counterparty_key_linkage(args, originator: nil)
        return @substrate.reveal_counterparty_key_linkage(args, originator: originator) if @substrate

        super
      end

      def reveal_specific_key_linkage(args, originator: nil)
        return @substrate.reveal_specific_key_linkage(args, originator: originator) if @substrate

        super
      end

      def encrypt(args, originator: nil)
        return @substrate.encrypt(args, originator: originator) if @substrate

        super
      end

      def decrypt(args, originator: nil)
        return @substrate.decrypt(args, originator: originator) if @substrate

        super
      end

      def create_hmac(args, originator: nil)
        return @substrate.create_hmac(args, originator: originator) if @substrate

        super
      end

      def verify_hmac(args, originator: nil)
        return @substrate.verify_hmac(args, originator: originator) if @substrate

        super
      end

      def create_signature(args, originator: nil)
        return @substrate.create_signature(args, originator: originator) if @substrate

        super
      end

      def verify_signature(args, originator: nil)
        return @substrate.verify_signature(args, originator: originator) if @substrate

        super
      end

      # Maximum ancestor depth to traverse when wiring source transactions.
      # Guards against stack overflow on pathologically deep or cyclic chains.
      ANCESTOR_DEPTH_CAP = 64

      # Rate-limits stale pending recovery to avoid O(n) scans on every
      # auto-fund call. Skips if called again within this interval.
      STALE_CHECK_INTERVAL = 30

      private

      # --- Identity helpers ---

      # Derives the wallet's identity P2PKH address.
      #
      # The network string 'mainnet'/'testnet' is mapped to the PublicKey
      # address method's +:network+ symbol (:mainnet/:testnet).
      #
      # @return [String] Base58Check-encoded P2PKH address
      def identity_address
        net = @network == 'testnet' ? :testnet : :mainnet
        @key_deriver.root_key.public_key.address(network: net)
      end

      # Returns true if an output with the given outpoint is already in storage,
      # regardless of its state (spendable, spent, or pending).
      # @param outpoint [String] outpoint in "txid.index" format
      # @return [Boolean]
      def output_exists?(outpoint)
        @storage.find_outputs({ outpoint: outpoint, include_spent: true, limit: 1, offset: 0 }).any?
      end

      # Returns true if the spendable pool contains any state-managed outputs.
      #
      # State-managed outputs are those with an explicit +:state+ field
      # (as opposed to the legacy +:spendable+ boolean used by
      # {#store_tracked_outputs} for basket token insertions). This distinction
      # allows auto-funding to trigger on payment receipts and chain UTXOs while
      # bypassing the gate for basket tracking outputs stored in no-input
      # transactions, which do not carry a spending key derivable by auto-fund.
      #
      # When no state-managed outputs are present, +create_action+ falls through
      # to the standard (no-input) path rather than attempting coin selection.
      # Callers needing forced auto-fund on an empty pool (e.g. explicit
      # +auto_fund: true+) bypass this check via the flag.
      #
      # @return [Boolean]
      def spendable_pool_eligible?
        @storage.find_spendable_outputs.any? { |o| o.key?(:state) }
      end

      # --- Auto-fund helpers ---

      # Orchestrates the full auto-fund flow: coin selection, fee convergence,
      # transaction building, signing, and state persistence.
      #
      # Selected UTXOs are immediately locked as +:pending+ (with a unique
      # reference) before building the transaction. If signing or finalisation
      # raises an error the lock is released and the UTXOs are returned to
      # +:spendable+ so they can be used by a subsequent attempt.
      #
      # @param args [Hash] original create_action params
      # @param caller_outputs [Array<Hash>] the caller-specified output specs
      # @return [Hash] finalised result with :txid and :tx
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

        # Atomically lock the selected UTXOs as pending to prevent concurrent
        # double-spend (closes the TOCTOU window between find and lock).
        fund_ref = "auto-fund-#{SecureRandom.hex(16)}"
        selected_outpoints = selection[:inputs].map { |u| u[:outpoint] }
        locked = @storage.lock_utxos(selected_outpoints, reference: fund_ref, no_send: no_send)

        # If another thread grabbed some UTXOs between selection and locking,
        # release what we did lock and raise — the caller can retry.
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

          # Persist the transaction first; only promote state once all writes succeed.
          @storage.store_transaction(txid, tx_hex)

          if no_send
            # Store change outputs directly as :pending with no_send: true so a
            # concurrent auto-fund cannot select them. No flip loop needed.
            change_outpoints = store_change_outputs(
              txid, tx, change_outputs, tx_hex,
              state: :pending, pending_reference: fund_ref, no_send: true
            )

            store_action(tx, args, status: 'nosend')
            store_tracked_outputs(txid, tx, caller_outputs)

            # Register in @pending so abort_action (or send_with) can release
            # inputs and remove change outputs. Secondary index by txid allows
            # send_with callers to look up pending entries by txid.
            @pending[fund_ref] = {
              tx: tx, args: args,
              locked_outpoints: selected_outpoints,
              change_outpoints: change_outpoints
            }
            @pending_by_txid[txid] = fund_ref

            beef_binary = tx.to_beef
            { txid: txid, tx: beef_binary.unpack('C*'), reference: fund_ref, no_send_change: change_outpoints }
          else
            # Store everything in pending state first — inputs are already locked
            # as :pending by lock_utxos above, so we match that discipline here.
            # Change outputs are stored directly as :pending to eliminate the
            # TOCTOU window where a concurrent auto-fund could select them.
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
          # Release the pending lock so the UTXOs are available for retry.
          release_pending_utxos(selected_outpoints, fund_ref)
          raise
        end
      end

      # Runs coin selection, raising {InsufficientFundsError} on failure.
      #
      # @param available [Array<Hash>] spendable UTXOs
      # @param target [Integer] total satoshis required by caller outputs
      # @param num_outputs [Integer] number of caller outputs
      # @return [Hash] coin selection result
      def auto_fund_select(available, target, num_outputs)
        auto_coin_selector.select(
          available: available,
          target_satoshis: target,
          num_outputs: num_outputs
        )
      end

      # Iteratively converges on a fee-stable set of change outputs.
      #
      # After initial selection, adding change outputs increases the transaction
      # size and therefore the fee. This method recalculates the fee with the
      # final output count and adjusts the excess until stable.
      #
      # @param selection [Hash] initial coin selection result
      # @param num_caller_outputs [Integer] number of caller-specified outputs
      # @return [Array<Hash>] finalised change output descriptors (may be empty)
      def converge_change(selection, num_caller_outputs)
        pool_opts = load_pool_opts

        change_outputs = auto_change_generator.generate(
          excess_satoshis: selection[:excess],
          num_existing_outputs: num_caller_outputs,
          **pool_opts
        )

        # Recalculate fee with the actual output count (caller + change).
        total_outputs = num_caller_outputs + change_outputs.size
        revised_fee = auto_fee_estimator.estimate(
          p2pkh_inputs: selection[:inputs].size,
          p2pkh_outputs: total_outputs
        )

        fee_delta = revised_fee - selection[:fee]
        return change_outputs if fee_delta.zero?

        # Adjust the excess to account for the revised fee and regenerate change.
        adjusted_excess = selection[:excess] - fee_delta
        return [] if adjusted_excess <= 0

        auto_change_generator.generate(
          excess_satoshis: adjusted_excess,
          num_existing_outputs: num_caller_outputs,
          **pool_opts
        )
      end

      # Loads pool health options for ChangeGenerator from stored settings.
      #
      # @return [Hash] keyword args for ChangeGenerator#generate
      def load_pool_opts
        params = @storage.find_setting('change_params')
        return {} unless params

        pool_size = @storage.find_spendable_outputs(basket: 'default').size
        { pool_size: pool_size, change_params: params }
      end

      # Builds the Transaction object for an auto-funded action.
      #
      # Inputs are wired with source data from storage and assigned P2PKH
      # unlocking templates using the derived private key. Outputs are built
      # from the caller specs followed by any change outputs.
      #
      # @param selected_utxos [Array<Hash>] UTXOs chosen by coin selection
      # @param caller_outputs [Array<Hash>] caller-specified output specs
      # @param change_outputs [Array<Hash>] change output descriptors from ChangeGenerator
      # @param args [Hash] original create_action params (for version/lock_time)
      # @return [BSV::Transaction::Transaction]
      def build_auto_funded_transaction(selected_utxos, caller_outputs, change_outputs, args)
        version   = args.fetch(:version, 1)
        lock_time = args.fetch(:lock_time, 0)
        tx = BSV::Transaction::Transaction.new(version: version, lock_time: lock_time)

        selected_utxos.each { |utxo| add_auto_funded_input(tx, utxo) }
        caller_outputs.each { |spec| add_output_from_spec(tx, spec) }
        change_outputs.each { |spec| add_output_from_spec(tx, spec) }

        # Randomise unless explicitly disabled
        shuffle_outputs(tx) if args.dig(:options, :randomize_outputs) != false && (caller_outputs.size + change_outputs.size) > 1

        tx
      end

      # Adds a single auto-funded input to the transaction, wiring source data
      # and attaching a P2PKH unlocking template using the derived private key.
      #
      # @param tx [BSV::Transaction::Transaction]
      # @param utxo [Hash] UTXO hash from storage
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

      # Adds a TransactionOutput to tx from an output spec hash.
      # Tags the output with its spec so store_tracked_outputs can find it
      # by object identity after shuffling.
      #
      # @param tx [BSV::Transaction::Transaction]
      # @param spec [Hash] output descriptor with :satoshis and :locking_script
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

      # Persists change outputs in storage with the specified state.
      #
      # Each output is stored with full BRC-29 derivation metadata so the
      # wallet can derive the spending key later. The +:state+ parameter
      # controls the initial state — pass +:pending+ with a +:pending_reference+
      # to store outputs atomically in the correct state and avoid any TOCTOU
      # window where a concurrent auto-fund could select them as spendable.
      #
      # @param txid [String] hex txid of the signed transaction
      # @param tx [BSV::Transaction::Transaction]
      # @param change_specs [Array<Hash>] change descriptors from {ChangeGenerator}
      # @param tx_hex [String] serialised transaction hex (used as source)
      # @param state [Symbol] initial output state (default: +:spendable+)
      # @param pending_reference [String, nil] reference tag for pending outputs
      # @param no_send [Boolean] when +true+, marks the output as no-send pending
      # @return [Array<String>] list of stored outpoints ("txid.vout" format)
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

      # Lazy accessors for auto-fund components. Created on first use so the
      # wallet is not penalised when the auto-fund path is never exercised.

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

      # Raises +WalletError+ when a broadcast is required but unavailable.
      #
      # Broadcast is required whenever +no_send+ is absent or false. Callers
      # that do not intend to broadcast on-chain must pass
      # +options: { no_send: true }+ to opt out.
      #
      # @param args [Hash] action arguments (merged, as seen at call site)
      # @raise [WalletError] if broadcast is needed but +broadcast_enabled?+ is false
      def validate_broadcast_configuration!(args)
        no_send = args.dig(:options, :no_send)
        return if no_send
        return if broadcast_enabled?

        raise WalletError,
              'create_action requires a broadcaster for on-chain broadcast. ' \
              'Pass broadcaster: BSV::Network::ARC.default to WalletClient.new, ' \
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

        # Randomise output order unless explicitly disabled
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
        # find_transaction expects display byte order (32 raw bytes)
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
        # Use include_spent: true so that outputs in :pending or :spent state
        # can still be wired — the lock was just placed by the auto-fund flow
        # and the source transaction data is still needed for signing.
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

        # Recursively wire ancestors of the source tx so to_beef can build a
        # complete, valid BEEF with the full proof chain.
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
          # Tag the output with its spec so store_tracked_outputs can find the
          # correct post-shuffle index, even when multiple outputs share the
          # same locking script and satoshis.
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

      # Reverts a set of outpoints from +:pending+ back to +:spendable+.
      #
      # Only releases an outpoint if its stored +:pending_reference+ matches
      # +ref+, to avoid accidentally unlocking UTXOs locked by a different
      # concurrent operation.
      #
      # @param outpoints [Array<String>] list of outpoints to release
      # @param ref [String] the reference used when locking
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

      # Rolls back a pending auto-funded action.
      #
      # Releases locked input UTXOs back to +:spendable+, deletes phantom change
      # outputs, and optionally updates the action status. Used by both
      # broadcast failure and +abort_action+ so UTXO state is always consistent.
      #
      # @param input_outpoints [Array<String>] outpoints locked as inputs
      # @param change_outpoints [Array<String>] change outputs to delete
      # @param txid [String, nil] txid of the action to update (may be nil)
      # @param ref [String] fund reference used when locking inputs
      # @param action_status [String, nil] new action status; nil skips the update
      def rollback_pending_action(input_outpoints, change_outpoints, txid, ref, action_status: nil)
        release_pending_utxos(input_outpoints, ref)
        Array(change_outpoints).each { |op| @storage.delete_output(op) }
        @storage.update_action_status(txid, action_status) if txid && action_status
      end

      # Delegates to the broadcast queue for auto-fund promotion.
      #
      # Kept as a thin wrapper so +promote_no_send+ callers (send_with path)
      # remain unaffected. The queue handles broadcast, UTXO promotion, and
      # rollback.
      #
      # @param tx [Transaction] signed transaction to broadcast
      # @param txid [String] hex transaction id
      # @param input_outpoints [Array<String>] outpoints locked as inputs
      # @param change_outpoints [Array<String>] change output outpoints
      # @param fund_ref [String] fund reference used when locking
      # @param beef_binary [String] raw BEEF bytes
      # @return [Hash] result hash from +BroadcastQueue#enqueue+
      def broadcast_and_promote(tx, txid, input_outpoints, change_outpoints, fund_ref, beef_binary)
        @broadcast_queue.enqueue(
          tx: tx, txid: txid, beef_binary: beef_binary,
          input_outpoints: input_outpoints,
          change_outpoints: change_outpoints,
          fund_ref: fund_ref,
          accept_delayed_broadcast: false
        )
      end

      # Batch-broadcasts a list of previously no_send transactions.
      #
      # Each txid must correspond to a pending no_send entry registered in
      # +@pending_by_txid+. Transactions are broadcast individually so that one
      # failure does not block the others. On per-tx success the inputs are
      # promoted to +:spent+ and change outputs to +:spendable+. On failure the
      # pending state is rolled back via +rollback_pending_action+.
      #
      # @param txids [Array<String>] txids of no_send transactions to broadcast
      # @return [Array<Hash>] per-tx results matching TS SDK +SendWithResult[]+ shape:
      #   +{ txid: String, status: 'unproven' | 'failed' }+
      def broadcast_send_with(txids)
        txids.map { |txid| broadcast_single_no_send(txid) }
      end

      # Broadcasts one no_send transaction and promotes or rolls back its state.
      #
      # @param txid [String] hex txid of the no_send transaction
      # @return [Hash] +{ txid:, status: }+ result entry
      def broadcast_single_no_send(txid)
        fund_ref = @pending_by_txid[txid]
        return { txid: txid, status: 'failed', error: 'Transaction not found in pending no_send store' } unless fund_ref

        pending_entry = @pending[fund_ref]
        unless pending_entry
          @pending_by_txid.delete(txid)
          return { txid: txid, status: 'failed', error: 'Pending entry expired or already processed' }
        end

        # Use the original signed transaction from the pending entry — it has
        # source_satoshis and source_locking_script wired on each input, which
        # the broadcaster needs for Extended Format (EF/BRC-30) submission.
        # Reconstructing from stored hex would lose that metadata.
        tx = pending_entry[:tx]
        unless tx
          tx_hex = @storage.find_transaction(txid)
          return { txid: txid, status: 'failed', error: 'Transaction not found' } unless tx_hex

          tx = BSV::Transaction::Transaction.from_hex(tx_hex)
        end
        promote_no_send(tx, txid, fund_ref, pending_entry)
      rescue StandardError => e
        # Catch unexpected errors outside the broadcast rescue block.
        { txid: txid, status: 'failed', error: e.message }
      end

      # Attempts to broadcast and promote a single no_send transaction.
      # Action status is set to 'unproven' (matching TS SDK SendWithResult)
      # because the transaction has been submitted but not yet confirmed.
      #
      # INVARIANT: Only broadcast failure triggers rollback. If broadcast succeeds
      # but promotion raises, the error propagates — confirmed on-chain outputs must
      # never be deleted. See +broadcast_and_promote+ for the same invariant.
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

        # Broadcast succeeded — promote state and remove from pending indices.
        # Do NOT rescue here: if promotion fails, the transaction is confirmed on-chain
        # and outputs must not be deleted. Let the error propagate to the caller.
        pending_entry[:locked_outpoints].each { |op| @storage.update_output_state(op, :spent) }
        pending_entry[:change_outpoints].each { |op| @storage.update_output_state(op, :spendable) }
        @storage.update_action_status(txid, 'unproven')
        @pending.delete(fund_ref)
        @pending_by_txid.delete(txid)

        { txid: txid, status: 'unproven' }
      end

      # Maps a broadcast exception to a {ReviewActionResultStatus} string.
      #
      # Delegates to +BroadcastQueue.status_for_error+ for a single source of
      # truth across all queue adapters.
      #
      # @param error [StandardError] the exception raised during broadcast
      # @return [String] one of 'doubleSpend', 'invalidTx', 'serviceError'
      def broadcast_status_for(error)
        BroadcastQueue.status_for_error(error)
      end

      def finalize_action(tx, args)
        tx.sign_all if tx.inputs.any?(&:unlocking_script_template)
        txid = tx.txid_hex

        no_send = args.dig(:options, :no_send)
        delayed = args.dig(:options, :accept_delayed_broadcast)

        status = if no_send
                   'nosend'
                 else
                   'pending'
                 end

        @storage.store_transaction(txid, tx.to_hex)
        store_action(tx, args, status: status)
        store_tracked_outputs(txid, tx, args[:outputs])

        beef_binary = tx.to_beef
        result = { txid: txid, tx: beef_binary.unpack('C*') }

        if no_send
          result[:no_send_change] = []
        else
          # The queue handles both broadcaster-present and no-broadcaster cases
          # internally, so no broadcast_enabled? check is needed here.
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
          # sequence is attr_reader only; re-set via instance_variable_set if provided
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

          # Find the actual post-shuffle index by matching the TransactionOutput object.
          # build_outputs stores a reference on each output via instance_variable_set(:@_spec)
          # so we can reliably map even when multiple outputs share the same script/satoshis.
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

        # BRC-29: derive the expected P2PKH key for this payment
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

        # BRC-52: verify the certifier's signature against the canonical
        # serialisation before persisting. Fixes F8.15 from the 2026-04-08
        # cross-SDK compliance review (#305) — prior to this check, callers
        # could pass any value in `args[:signature]` and it would be stored
        # as if certifier-authentic.
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

        # BRC-52: the certifier's HTTP response is untrusted network data;
        # verify the signature before persisting. Closes the F8.15 class of
        # bug on the issuance path too (the finding's "Same issue as F8.15"
        # note from F8.16).
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
