# frozen_string_literal: true

require 'securerandom'
require 'base64'
require 'net/http'
require 'json'
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

      # @return [ChainProvider] the blockchain data provider
      attr_reader :chain_provider

      # @return [String] the network ('mainnet' or 'testnet')
      attr_reader :network

      # @param key [BSV::Primitives::PrivateKey, String, KeyDeriver] signing key
      # @param storage [StorageAdapter] persistence adapter (default: MemoryStore)
      # @param network [String] 'mainnet' (default) or 'testnet'
      # @param chain_provider [ChainProvider] blockchain data provider (default: NullChainProvider)
      # @param http_client [#request, nil] injectable HTTP client for certificate issuance
      def initialize(key, storage: MemoryStore.new, network: 'mainnet', chain_provider: NullChainProvider.new, http_client: nil)
        super(key)
        @storage = storage
        @network = network
        @chain_provider = chain_provider
        @http_client = http_client
        @pending = {}
      end

      # --- Transaction Operations ---

      # Creates a new Bitcoin transaction.
      #
      # If all inputs carry unlocking_script values, the transaction is
      # finalised immediately and returned with :txid and :tx (BEEF bytes).
      # If any input specifies only unlocking_script_length, the transaction
      # is held pending and returned as a signable_transaction for external
      # signing via {#sign_action}.
      #
      # @param args [Hash] transaction parameters
      # @param _originator [String, nil] FQDN of the originating application
      # @return [Hash] finalised result or signable_transaction
      def create_action(args, _originator: nil)
        validate_create_action!(args)
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
      def sign_action(args, _originator: nil)
        reference = args[:reference]
        pending = @pending[reference]
        raise WalletError, 'Transaction not found for the given reference' unless pending

        tx = pending[:tx]
        apply_spends(tx, args[:spends])
        @pending.delete(reference)
        finalize_action(tx, pending[:args])
      end

      # Aborts a pending signable transaction.
      #
      # @param args [Hash]
      # @option args [String] :reference base64 reference to abort
      # @param _originator [String, nil] FQDN of the originating application
      # @return [Hash] { aborted: true }
      def abort_action(args, _originator: nil)
        reference = args[:reference]
        raise WalletError, 'Transaction not found for the given reference' unless @pending.key?(reference)

        @pending.delete(reference)
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
      def list_actions(args, _originator: nil)
        validate_list_actions!(args)
        query = build_action_query(args)
        total = @storage.count_actions(query)
        actions = @storage.find_actions(query)
        { total_actions: total, actions: actions }
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
      def list_outputs(args, _originator: nil)
        validate_list_outputs!(args)
        query = build_output_query(args)
        total = @storage.count_outputs(query)
        outputs = @storage.find_outputs(query)
        { total_outputs: total, outputs: outputs }
      end

      # Removes an output from basket tracking.
      #
      # @param args [Hash]
      # @option args [String] :basket basket name
      # @option args [String] :output outpoint string
      # @param _originator [String, nil] FQDN of the originating application
      # @return [Hash] { relinquished: true }
      def relinquish_output(args, _originator: nil)
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
      def internalize_action(args, _originator: nil)
        validate_internalize_action!(args)
        beef_binary = args[:tx].pack('C*')
        beef = BSV::Transaction::Beef.from_binary(beef_binary)
        tx = extract_subject_transaction(beef)

        process_internalize_outputs(tx, args[:outputs])
        store_action(tx, args, status: 'completed')
        { accepted: true }
      end

      # --- Blockchain & Network Data ---

      # Returns the current blockchain height from the chain provider.
      #
      # @param _args [Hash] unused (empty hash)
      # @return [Hash] { height: Integer }
      def get_height(_args = {}, _originator: nil)
        { height: @chain_provider.get_height }
      end

      # Returns the block header at the given height from the chain provider.
      #
      # @param args [Hash]
      # @option args [Integer] :height block height
      # @return [Hash] { header: String } 80-byte hex-encoded block header
      def get_header_for_height(args, _originator: nil)
        raise InvalidParameterError.new('height', 'a positive Integer') unless args[:height].is_a?(Integer) && args[:height].positive?

        { header: @chain_provider.get_header(args[:height]) }
      end

      # Returns the network this wallet is configured for.
      #
      # @param _args [Hash] unused (empty hash)
      # @return [Hash] { network: String } 'mainnet' or 'testnet'
      def get_network(_args = {}, _originator: nil)
        { network: @network }
      end

      # Returns the wallet version string.
      #
      # @param _args [Hash] unused (empty hash)
      # @return [Hash] { version: String } in vendor-major.minor.patch format
      def get_version(_args = {}, _originator: nil)
        { version: "bsv-wallet-#{BSV::WalletInterface::VERSION}" }
      end

      # --- Authentication ---

      # Checks whether the user is authenticated.
      # For local wallets with a private key, this is always true.
      #
      # @param _args [Hash] unused (empty hash)
      # @return [Hash] { authenticated: Boolean }
      def is_authenticated(_args = {}, _originator: nil)
        { authenticated: true }
      end

      # Waits until the user is authenticated.
      # For local wallets, returns immediately.
      #
      # @param _args [Hash] unused (empty hash)
      # @return [Hash] { authenticated: true }
      def wait_for_authentication(_args = {}, _originator: nil)
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
      def acquire_certificate(args, _originator: nil)
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
      def list_certificates(args, _originator: nil)
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
      def prove_certificate(args, _originator: nil)
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
                                protocol_id: [2, 'certificate field revelation'],
                                key_id: "#{cert_arg[:type]} #{cert_arg[:serial_number]} #{field_name}",
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
      def relinquish_certificate(args, _originator: nil)
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
      def discover_by_identity_key(args, _originator: nil)
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
      def discover_by_attributes(args, _originator: nil)
        raise InvalidParameterError.new('attributes', 'a non-empty Hash') unless args[:attributes].is_a?(Hash) && !args[:attributes].empty?

        query = { attributes: args[:attributes], limit: args[:limit] || 10, offset: args[:offset] || 0 }
        total = @storage.count_certificates(query)
        certs = @storage.find_certificates(query)
        { total_certificates: total, certificates: certs.map { |c| cert_without_keyring(c) } }
      end

      private

      # --- Validation ---

      def validate_create_action!(args)
        Validators.validate_description!(args[:description])
        inputs_present = args[:inputs] && !args[:inputs].empty?
        outputs_present = args[:outputs] && !args[:outputs].empty?
        raise InvalidParameterError.new('inputs/outputs', 'at least one input or output') unless inputs_present || outputs_present

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

          input.unlocking_script = BSV::Script::Script.from_hex(spec[:unlocking_script]) if spec[:unlocking_script]

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

      def finalize_action(tx, args)
        txid = tx.txid_hex
        status = args.dig(:options, :no_send) ? 'nosend' : 'completed'

        store_action(tx, args, status: status)
        store_tracked_outputs(txid, tx, args[:outputs])

        beef_binary = tx.to_beef
        result = { txid: txid, tx: beef_binary.unpack('C*') }
        result[:no_send_change] = [] if args.dig(:options, :no_send)
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
                                  spendable: true
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

      # --- Internalize helpers ---

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

        output_specs.each do |spec|
          output_index = spec[:output_index]
          tx_output = tx.outputs[output_index]
          raise WalletError, "Output index #{output_index} not found in transaction" unless tx_output

          case spec[:protocol]
          when 'wallet payment'
            internalize_payment(txid, output_index, tx_output, spec[:payment_remittance])
          when 'basket insertion'
            internalize_basket(txid, output_index, tx_output, spec[:insertion_remittance])
          else
            raise InvalidParameterError.new('protocol', '"wallet payment" or "basket insertion"')
          end
        end
      end

      def internalize_payment(txid, output_index, tx_output, remittance)
        unless remittance
          raise InvalidParameterError.new('payment_remittance',
                                          'present for wallet payment protocol')
        end

        sender_key = remittance[:sender_identity_key]
        prefix = remittance[:derivation_prefix]
        suffix = remittance[:derivation_suffix]

        # BRC-29: derive the expected P2PKH key for this payment
        derived_pub = @key_deriver.derive_public_key(
          [2, '3241645161d8'],
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
                                spendable: true,
                                sender_identity_key: sender_key,
                                derivation_prefix: prefix,
                                derivation_suffix: suffix
                              })
      end

      def internalize_basket(txid, output_index, tx_output, remittance)
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
                                spendable: true
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
        {
          type: args[:type],
          subject: @key_deriver.identity_key,
          serial_number: args[:serial_number],
          certifier: args[:certifier],
          revocation_outpoint: args[:revocation_outpoint],
          signature: args[:signature],
          fields: args[:fields],
          keyring: args[:keyring_for_subject]
        }
      end

      def acquire_via_issuance(args)
        uri = URI(args[:certifier_url])
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request.body = JSON.generate({
                                       type: args[:type],
                                       subject: @key_deriver.identity_key,
                                       certifier: args[:certifier],
                                       fields: args[:fields]
                                     })

        response = execute_http(uri, request)
        code = response.code.to_i

        raise WalletError, "Certificate issuance failed: HTTP #{code}" unless (200..299).cover?(code)

        body = JSON.parse(response.body)

        {
          type: body['type'] || args[:type],
          subject: @key_deriver.identity_key,
          serial_number: body['serialNumber'],
          certifier: args[:certifier],
          revocation_outpoint: body['revocationOutpoint'],
          signature: body['signature'],
          fields: body['fields'] || args[:fields],
          keyring: body['keyringForSubject']
        }
      rescue JSON::ParserError
        raise WalletError, 'Certificate issuance failed: invalid JSON response'
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
