# frozen_string_literal: true

module BSV
  module Wallet
    # BRC-100 abstract wallet interface — all 28 methods.
    #
    # Include this module and override the methods your implementation supports.
    # Unimplemented methods raise +NotImplementedError+.
    #
    # The 28 methods are grouped into six functional areas matching
    # the BRC-100 Interface Structure specification.
    #
    # @example
    #   class MyWallet
    #     include BSV::Wallet::Interface::BRC100
    #
    #     def get_height(originator: nil)
    #       { height: 800_000 }
    #     end
    #   end
    module Interface
      module BRC100
        # --- Transaction Operations (codes 1-7) ---

        # Creates a new Bitcoin transaction.
        #
        # @param description [String] human-readable description (5-50 chars)
        # @param inputs [Array<Hash>] optional inputs to consume
        #   - :outpoint [String] txid.index being consumed
        #   - :unlocking_script [String] hex unlocking script
        #   - :unlocking_script_length [Integer] length, if script provided later via {#sign_action}
        #   - :input_description [String] what this input consumes (5-50 chars)
        #   - :sequence_number [Integer] optional sequence number
        # @param outputs [Array<Hash>] optional outputs to create
        #   - :locking_script [String] hex locking script
        #   - :satoshis [Integer] output value
        #   - :output_description [String] what this output represents (5-50 chars)
        #   - :basket [String] optional basket name for UTXO tracking
        #   - :custom_instructions [String] application-specific context
        #   - :tags [Array<String>] output tags for filtering
        # @return [Hash] BRC-100 spec-mandated keys: :txid (display-order hex), :tx, :no_send_change,
        #   :send_with_results, :signable_transaction
        def create_action(description:, input_beef: nil, inputs: nil, outputs: nil,
                          lock_time: nil, version: nil, labels: nil,
                          sign_and_process: true, accept_delayed_broadcast: true,
                          # BRC-100 spec-mandated parameter names — display-order hex txids
                          trust_self: nil, known_txids: nil, return_txid_only: false,
                          no_send: false, no_send_change: nil, send_with: nil,
                          randomize_outputs: true, originator: nil)
          raise NotImplementedError
        end

        # Signs a transaction previously created with {#create_action}.
        #
        # @param spends [Hash{Integer => Hash}] input index => { unlocking_script:, sequence_number: }
        # @param reference [String] reference returned by {#create_action}
        def sign_action(spends:, reference:,
                        accept_delayed_broadcast: true,
                        return_txid_only: false, # BRC-100 spec-mandated parameter name
                        no_send: false, send_with: nil, originator: nil)
          raise NotImplementedError
        end

        # Aborts a transaction that has not yet been finalized.
        def abort_action(reference:, originator: nil)
          raise NotImplementedError
        end

        # Lists transactions matching the specified labels.
        #
        # @return [Hash] :total_actions, :actions
        def list_actions(labels:, label_query_mode: :any,
                         include_labels: false, include_inputs: false,
                         include_input_source_locking_scripts: false,
                         include_input_unlocking_scripts: false,
                         include_outputs: false, include_output_locking_scripts: false,
                         limit: 10, offset: 0, seek_permission: true, originator: nil)
          raise NotImplementedError
        end

        # Internalizes a transaction — labels it, pays outputs to the wallet balance,
        # inserts outputs into baskets, and/or tags them.
        #
        # @param tx [Array<Integer>] Atomic BEEF-formatted transaction (byte array)
        # @param outputs [Array<Hash>] metadata per output
        #   - :output_index [Integer] index within the transaction
        #   - :protocol [Symbol] :wallet_payment or :basket_insertion
        #   - :payment_remittance [Hash] for payments: { derivation_prefix:, derivation_suffix:, sender_identity_key: }
        #   - :insertion_remittance [Hash] for insertions: { basket:, custom_instructions:, tags: }
        def internalize_action(tx:, outputs:, description:, labels: nil,
                               seek_permission: true, originator: nil)
          raise NotImplementedError
        end

        # Lists spendable outputs in a basket.
        #
        # @param include [Symbol] nil, :locking_scripts, or :entire_transactions
        # @return [Hash] :total_outputs, :beef, :outputs
        def list_outputs(basket:, tags: nil, tag_query_mode: :any, include: nil,
                         include_custom_instructions: false, include_tags: false,
                         include_labels: false, limit: 10, offset: 0,
                         seek_permission: true, originator: nil)
          raise NotImplementedError
        end

        # Removes an output from a basket without spending it.
        def relinquish_output(basket:, output:, originator: nil)
          raise NotImplementedError
        end

        # --- Public Key Management (codes 8-10) ---

        # Retrieves a derived or identity public key.
        #
        # @param protocol_id [Array(Integer, String)] security level (0-2) and protocol string
        # @param counterparty [String] public key hex, 'self', or 'anyone'
        # @return [Hash] :public_key
        def get_public_key(identity_key: false, protocol_id: nil, key_id: nil,
                           privileged: false, privileged_reason: nil,
                           counterparty: nil, for_self: false,
                           seek_permission: true, originator: nil)
          raise NotImplementedError
        end

        # Reveals key linkage with a counterparty to a verifier, across all interactions.
        def reveal_counterparty_key_linkage(counterparty:, verifier:,
                                            privileged: false, privileged_reason: nil,
                                            originator: nil)
          raise NotImplementedError
        end

        # Reveals key linkage for a specific protocol and key interaction.
        def reveal_specific_key_linkage(counterparty:, verifier:, protocol_id:, key_id:,
                                        privileged: false, privileged_reason: nil,
                                        originator: nil)
          raise NotImplementedError
        end

        # --- Cryptography Operations (codes 11-16) ---

        # Encrypts plaintext using derived keys.
        def encrypt(plaintext:, protocol_id:, key_id:,
                    privileged: false, privileged_reason: nil,
                    counterparty: nil, seek_permission: true, originator: nil)
          raise NotImplementedError
        end

        # Decrypts ciphertext using derived keys.
        def decrypt(ciphertext:, protocol_id:, key_id:,
                    privileged: false, privileged_reason: nil,
                    counterparty: nil, seek_permission: true, originator: nil)
          raise NotImplementedError
        end

        # Creates an HMAC for the provided data.
        def create_hmac(data:, protocol_id:, key_id:,
                        privileged: false, privileged_reason: nil,
                        counterparty: nil, seek_permission: true, originator: nil)
          raise NotImplementedError
        end

        # Verifies an HMAC against the provided data.
        def verify_hmac(data:, hmac:, protocol_id:, key_id:,
                        privileged: false, privileged_reason: nil,
                        counterparty: nil, seek_permission: true, originator: nil)
          raise NotImplementedError
        end

        # Creates a digital signature (ECDSA) for data or a pre-computed hash.
        def create_signature(protocol_id:, key_id:, data: nil, hash_to_directly_sign: nil,
                             privileged: false, privileged_reason: nil,
                             counterparty: nil, seek_permission: true, originator: nil)
          raise NotImplementedError
        end

        # Verifies a digital signature against data or a pre-computed hash.
        def verify_signature(signature:, protocol_id:, key_id:, data: nil,
                             hash_to_directly_verify: nil,
                             privileged: false, privileged_reason: nil,
                             counterparty: nil, for_self: false,
                             seek_permission: true, originator: nil)
          raise NotImplementedError
        end

        # --- Identity and Certificate Management (codes 17-22) ---

        # Acquires an identity certificate from a certifier or by direct receipt.
        #
        # @param acquisition_protocol [Symbol] :direct or :issuance
        # @param fields [Hash{String => String}] certificate field names to values
        def acquire_certificate(type:, certifier:, acquisition_protocol:, fields:,
                                serial_number: nil, revocation_outpoint: nil,
                                signature: nil, certifier_url: nil,
                                keyring_revealer: nil, keyring_for_subject: nil,
                                privileged: false, privileged_reason: nil, originator: nil)
          raise NotImplementedError
        end

        # Lists identity certificates filtered by certifier(s) and type(s).
        def list_certificates(certifiers:, types:, limit: 10, offset: 0,
                              privileged: false, privileged_reason: nil, originator: nil)
          raise NotImplementedError
        end

        # Proves select fields of a certificate to a verifier.
        #
        # @param certificate [Hash] the full certificate (type, subject, serial_number,
        #   certifier, revocation_outpoint, signature, fields)
        # @param fields_to_reveal [Array<String>] field names to disclose
        def prove_certificate(certificate:, fields_to_reveal:, verifier:,
                              privileged: false, privileged_reason: nil, originator: nil)
          raise NotImplementedError
        end

        # Removes a certificate from the wallet.
        def relinquish_certificate(type:, serial_number:, certifier:, originator: nil)
          raise NotImplementedError
        end

        # Discovers certificates issued to a given identity key.
        def discover_by_identity_key(identity_key:, limit: 10, offset: 0,
                                     seek_permission: true, originator: nil)
          raise NotImplementedError
        end

        # Discovers certificates matching specific attribute values.
        #
        # @param attributes [Hash{String => String}] field name/value pairs to match
        def discover_by_attributes(attributes:, limit: 10, offset: 0,
                                   seek_permission: true, originator: nil)
          raise NotImplementedError
        end

        # --- Authentication (codes 23-24) ---

        # Checks whether the user is authenticated.
        def authenticated?(originator: nil)
          raise NotImplementedError
        end

        # Blocks until the user is authenticated.
        def wait_for_authentication(originator: nil)
          raise NotImplementedError
        end

        # --- Blockchain and Network Data (codes 25-28) ---

        # Returns the current blockchain height.
        def get_height(originator: nil)
          raise NotImplementedError
        end

        # Returns the 80-byte block header at the given height.
        def get_header_for_height(height:, originator: nil)
          raise NotImplementedError
        end

        # Returns the network (:mainnet or :testnet).
        def get_network(originator: nil)
          raise NotImplementedError
        end

        # Returns the wallet version string.
        def get_version(originator: nil)
          raise NotImplementedError
        end
      end
    end
  end
end
