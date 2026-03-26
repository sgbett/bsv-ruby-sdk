# frozen_string_literal: true

module BSV
  module Wallet
    # BRC-100 Wallet Interface
    #
    # Defines the 28 methods of the standard BSV wallet-to-application interface.
    # Include this module and override the methods your implementation supports.
    # Unimplemented methods raise {UnsupportedActionError}.
    module Interface
      # rubocop:disable Lint/UnusedMethodArgument

      # --- Transaction Operations ---

      # Creates a new Bitcoin transaction with metadata and labels.
      #
      # @param args [Hash] transaction parameters
      # @option args [String] :description (required) 5-50 char description
      # @option args [Array<Integer>] :input_beef BEEF data for inputs
      # @option args [Array<Hash>] :inputs input objects with :outpoint, :unlocking_script, :input_description
      # @option args [Array<Hash>] :outputs output objects with :locking_script, :satoshis, :output_description
      # @option args [Integer] :lock_time optional lock time
      # @option args [Integer] :version optional transaction version
      # @option args [Array<String>] :labels optional transaction labels
      # @option args [Hash] :options optional processing options
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] with :txid, :tx, :no_send_change, :send_with_results, :signable_transaction
      def create_action(args, originator: nil)
        raise UnsupportedActionError, 'create_action'
      end

      # Signs a previously created transaction.
      #
      # @param args [Hash] signing parameters
      # @option args [Hash] :spends map of input indexes to unlocking scripts
      # @option args [String] :reference base64 reference from create_action
      # @option args [Hash] :options optional processing options
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] with :txid, :tx, :send_with_results
      def sign_action(args, originator: nil)
        raise UnsupportedActionError, 'sign_action'
      end

      # Aborts an incomplete transaction.
      #
      # @param args [Hash]
      # @option args [String] :reference base64 reference to abort
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] { aborted: true }
      def abort_action(args, originator: nil)
        raise UnsupportedActionError, 'abort_action'
      end

      # Lists transactions matching the specified labels.
      #
      # @param args [Hash] query parameters
      # @option args [Array<String>] :labels (required) labels to filter by
      # @option args [String] :label_query_mode 'any' or 'all'
      # @option args [Boolean] :include_labels include labels in results
      # @option args [Boolean] :include_inputs include input details
      # @option args [Boolean] :include_outputs include output details
      # @option args [Integer] :limit max results (default 10, max 10000)
      # @option args [Integer] :offset number to skip
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] with :total_actions, :actions
      def list_actions(args, originator: nil)
        raise UnsupportedActionError, 'list_actions'
      end

      # Accepts an incoming transaction for internalization.
      #
      # @param args [Hash]
      # @option args [Array<Integer>] :tx Atomic BEEF-formatted transaction
      # @option args [Array<Hash>] :outputs metadata about outputs
      # @option args [String] :description 5-50 char description
      # @option args [Array<String>] :labels optional labels
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] { accepted: true }
      def internalize_action(args, originator: nil)
        raise UnsupportedActionError, 'internalize_action'
      end

      # Lists spendable outputs in a basket.
      #
      # @param args [Hash]
      # @option args [String] :basket (required) basket name
      # @option args [Array<String>] :tags optional tag filter
      # @option args [String] :tag_query_mode 'any' or 'all'
      # @option args [String] :include 'locking scripts' or 'entire transactions'
      # @option args [Integer] :limit max results
      # @option args [Integer] :offset number to skip
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] with :total_outputs, :outputs
      def list_outputs(args, originator: nil)
        raise UnsupportedActionError, 'list_outputs'
      end

      # Releases an output from basket tracking.
      #
      # @param args [Hash]
      # @option args [String] :basket basket name
      # @option args [String] :output outpoint string
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] { relinquished: true }
      def relinquish_output(args, originator: nil)
        raise UnsupportedActionError, 'relinquish_output'
      end

      # --- Public Key Management ---

      # Retrieves a derived or identity public key.
      #
      # @param args [Hash]
      # @option args [Boolean] :identity_key if true, return the identity key
      # @option args [Array] :protocol_id [security_level, protocol_name]
      # @option args [String] :key_id key identifier
      # @option args [String] :counterparty public key hex, 'self', or 'anyone'
      # @option args [Boolean] :for_self derive from own identity
      # @option args [Boolean] :privileged privileged mode
      # @option args [String] :privileged_reason reason for privileged access
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] { public_key: String }
      def get_public_key(args, originator: nil)
        raise UnsupportedActionError, 'get_public_key'
      end

      # Reveals key linkage between self and a counterparty to a verifier.
      #
      # @param args [Hash]
      # @option args [String] :counterparty counterparty public key hex
      # @option args [String] :verifier verifier public key hex
      # @option args [Boolean] :privileged privileged mode
      # @option args [String] :privileged_reason reason for privileged access
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] with :prover, :verifier, :counterparty, :revelation_time, :encrypted_linkage, :encrypted_linkage_proof
      def reveal_counterparty_key_linkage(args, originator: nil)
        raise UnsupportedActionError, 'reveal_counterparty_key_linkage'
      end

      # Reveals specific key linkage for a particular interaction.
      #
      # @param args [Hash]
      # @option args [String] :counterparty counterparty public key hex
      # @option args [String] :verifier verifier public key hex
      # @option args [Array] :protocol_id [security_level, protocol_name]
      # @option args [String] :key_id key identifier
      # @option args [Boolean] :privileged privileged mode
      # @option args [String] :privileged_reason reason for privileged access
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] with :prover, :verifier, :counterparty, :protocol_id, :key_id, :encrypted_linkage, :encrypted_linkage_proof, :proof_type
      def reveal_specific_key_linkage(args, originator: nil)
        raise UnsupportedActionError, 'reveal_specific_key_linkage'
      end

      # --- Cryptography Operations ---

      # Encrypts data using a derived symmetric key.
      #
      # @param args [Hash]
      # @option args [Array<Integer>] :plaintext byte array to encrypt
      # @option args [Array] :protocol_id [security_level, protocol_name]
      # @option args [String] :key_id key identifier
      # @option args [String] :counterparty public key hex, 'self', or 'anyone'
      # @option args [Boolean] :privileged privileged mode
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] { ciphertext: Array<Integer> }
      def encrypt(args, originator: nil)
        raise UnsupportedActionError, 'encrypt'
      end

      # Decrypts data using a derived symmetric key.
      #
      # @param args [Hash]
      # @option args [Array<Integer>] :ciphertext byte array to decrypt
      # @option args [Array] :protocol_id [security_level, protocol_name]
      # @option args [String] :key_id key identifier
      # @option args [String] :counterparty public key hex, 'self', or 'anyone'
      # @option args [Boolean] :privileged privileged mode
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] { plaintext: Array<Integer> }
      def decrypt(args, originator: nil)
        raise UnsupportedActionError, 'decrypt'
      end

      # Creates an HMAC using a derived symmetric key.
      #
      # @param args [Hash]
      # @option args [Array<Integer>] :data byte array
      # @option args [Array] :protocol_id [security_level, protocol_name]
      # @option args [String] :key_id key identifier
      # @option args [String] :counterparty public key hex, 'self', or 'anyone'
      # @option args [Boolean] :privileged privileged mode
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] { hmac: Array<Integer> }
      def create_hmac(args, originator: nil)
        raise UnsupportedActionError, 'create_hmac'
      end

      # Verifies an HMAC using a derived symmetric key.
      #
      # @param args [Hash]
      # @option args [Array<Integer>] :data byte array
      # @option args [Array<Integer>] :hmac HMAC to verify
      # @option args [Array] :protocol_id [security_level, protocol_name]
      # @option args [String] :key_id key identifier
      # @option args [String] :counterparty public key hex, 'self', or 'anyone'
      # @option args [Boolean] :privileged privileged mode
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] { valid: true }
      def verify_hmac(args, originator: nil)
        raise UnsupportedActionError, 'verify_hmac'
      end

      # Creates a digital signature using a derived private key.
      #
      # @param args [Hash]
      # @option args [Array<Integer>] :data data to sign
      # @option args [Array<Integer>] :hash_to_directly_sign pre-hashed data to sign
      # @option args [Array] :protocol_id [security_level, protocol_name]
      # @option args [String] :key_id key identifier
      # @option args [String] :counterparty public key hex, 'self', or 'anyone'
      # @option args [Boolean] :privileged privileged mode
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] { signature: Array<Integer> }
      def create_signature(args, originator: nil)
        raise UnsupportedActionError, 'create_signature'
      end

      # Verifies a digital signature using a derived public key.
      #
      # @param args [Hash]
      # @option args [Array<Integer>] :data original data
      # @option args [Array<Integer>] :hash_to_directly_verify pre-hashed data
      # @option args [Array<Integer>] :signature DER-encoded signature
      # @option args [Array] :protocol_id [security_level, protocol_name]
      # @option args [String] :key_id key identifier
      # @option args [String] :counterparty public key hex, 'self', or 'anyone'
      # @option args [Boolean] :for_self verify own signature
      # @option args [Boolean] :privileged privileged mode
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] { valid: true }
      def verify_signature(args, originator: nil)
        raise UnsupportedActionError, 'verify_signature'
      end

      # --- Identity and Certificate Management ---

      # Acquires an identity certificate.
      #
      # @param args [Hash]
      # @option args [String] :type certificate type (base64)
      # @option args [String] :certifier certifier public key hex
      # @option args [String] :acquisition_protocol 'direct' or 'issuance'
      # @option args [Hash] :fields certificate fields
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] certificate data
      def acquire_certificate(args, originator: nil)
        raise UnsupportedActionError, 'acquire_certificate'
      end

      # Lists identity certificates.
      #
      # @param args [Hash]
      # @option args [Array<String>] :certifiers certifier public keys
      # @option args [Array<String>] :types certificate types
      # @option args [Integer] :limit max results
      # @option args [Integer] :offset number to skip
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] with :total_certificates, :certificates
      def list_certificates(args, originator: nil)
        raise UnsupportedActionError, 'list_certificates'
      end

      # Proves select fields of a certificate to a verifier.
      #
      # @param args [Hash]
      # @option args [Hash] :certificate the certificate to prove
      # @option args [Array<String>] :fields_to_reveal field names to reveal
      # @option args [String] :verifier verifier public key hex
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] { keyring_for_verifier: Hash }
      def prove_certificate(args, originator: nil)
        raise UnsupportedActionError, 'prove_certificate'
      end

      # Removes a certificate from the wallet.
      #
      # @param args [Hash]
      # @option args [String] :type certificate type
      # @option args [String] :serial_number certificate serial number
      # @option args [String] :certifier certifier public key hex
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] { relinquished: true }
      def relinquish_certificate(args, originator: nil)
        raise UnsupportedActionError, 'relinquish_certificate'
      end

      # Discovers certificates by identity key.
      #
      # @param args [Hash]
      # @option args [String] :identity_key public key hex to search
      # @option args [Integer] :limit max results
      # @option args [Integer] :offset number to skip
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] with :total_certificates, :certificates
      def discover_by_identity_key(args, originator: nil)
        raise UnsupportedActionError, 'discover_by_identity_key'
      end

      # Discovers certificates by attributes.
      #
      # @param args [Hash]
      # @option args [Hash] :attributes attribute name/value pairs to match
      # @option args [Integer] :limit max results
      # @option args [Integer] :offset number to skip
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] with :total_certificates, :certificates
      def discover_by_attributes(args, originator: nil)
        raise UnsupportedActionError, 'discover_by_attributes'
      end

      # --- Blockchain and Network Data ---

      # Returns the current blockchain height.
      #
      # @param args [Hash] empty hash
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] { height: Integer }
      def get_height(args = {}, originator: nil)
        raise UnsupportedActionError, 'get_height'
      end

      # Returns the block header at a given height.
      #
      # @param args [Hash]
      # @option args [Integer] :height block height
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] { header: String }
      def get_header_for_height(args, originator: nil)
        raise UnsupportedActionError, 'get_header_for_height'
      end

      # Returns the network (mainnet or testnet).
      #
      # @param args [Hash] empty hash
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] { network: String }
      def get_network(args = {}, originator: nil)
        raise UnsupportedActionError, 'get_network'
      end

      # Returns the wallet version string.
      #
      # @param args [Hash] empty hash
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] { version: String }
      def get_version(args = {}, originator: nil)
        raise UnsupportedActionError, 'get_version'
      end

      # --- Authentication ---

      # Checks if the user is authenticated.
      #
      # @param args [Hash] empty hash
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] { authenticated: Boolean }
      def is_authenticated(args = {}, originator: nil)
        raise UnsupportedActionError, 'is_authenticated'
      end

      # Waits until the user is authenticated.
      #
      # @param args [Hash] empty hash
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] { authenticated: true }
      def wait_for_authentication(args = {}, originator: nil)
        raise UnsupportedActionError, 'wait_for_authentication'
      end

      # rubocop:enable Lint/UnusedMethodArgument
    end
  end
end
