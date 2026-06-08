# frozen_string_literal: true

require 'json'

module BSV
  module Identity
    # Client for resolving and publishing identity information on the BSV overlay network.
    #
    # Wraps wallet discovery and overlay broadcasting to provide a high-level
    # interface for the BSV Identity protocol:
    #
    # - Resolve identities by key or attributes via {#resolve_by_identity_key} and
    #   {#resolve_by_attributes}.
    # - Publicly reveal certificate fields on-chain via {#publicly_reveal_attributes}.
    # - Revoke an existing revelation via {#revoke_certificate_revelation}.
    #
    # All overlay dependencies (broadcaster, resolver) are injectable for testing.
    #
    # @example Resolve an identity
    #   client = BSV::Identity::Client.new(wallet: my_wallet)
    #   identities = client.resolve_by_identity_key(identity_key: pubkey_hex)
    #
    # @example Publicly reveal certificate fields
    #   client = BSV::Identity::Client.new(wallet: my_wallet, broadcaster: my_broadcaster)
    #   result = client.publicly_reveal_attributes(certificate, fields_to_reveal: ['email'])
    class Client
      # Default certificate verifier — raises NotImplementedError because certificate
      # verification depends on BSV::Auth::Certificate, which is a separate HLR.
      DEFAULT_VERIFIER = lambda do |_certificate|
        raise NotImplementedError,
              'Certificate verification requires BSV::Auth::Certificate (not yet implemented)'
      end

      # @param wallet [#discover_by_identity_key, #discover_by_attributes,
      #   #prove_certificate, #create_action, #get_network] BRC-100 wallet interface
      # @param options [ClientOptions, nil] identity protocol options (default: ClientOptions::DEFAULT)
      # @param originator [String, nil] optional FQDN of the originating application
      # @param certificate_verifier [#call, nil] callable that verifies a certificate;
      #   defaults to a lambda that raises NotImplementedError
      # @param broadcaster [BSV::Overlay::TopicBroadcaster, nil] injectable broadcaster;
      #   built from the wallet's network preset when nil
      # @param resolver [BSV::Overlay::LookupResolver, nil] injectable lookup resolver;
      #   built from the wallet's network preset when nil
      def initialize(
        wallet:,
        options: nil,
        originator: nil,
        certificate_verifier: nil,
        broadcaster: nil,
        resolver: nil
      )
        @wallet               = wallet
        @options              = options || default_options
        @originator           = originator
        @certificate_verifier = certificate_verifier || DEFAULT_VERIFIER
        @broadcaster          = broadcaster
        @resolver             = resolver
      end

      # Resolves displayable identities issued to a given identity key.
      #
      # Delegates to the wallet's +discover_by_identity_key+ and maps each
      # returned certificate through {IdentityParser.parse}.
      #
      # @param identity_key [String] compressed public key hex
      # @param limit [Integer, nil] maximum number of certificates to return
      # @param offset [Integer, nil] number of certificates to skip
      # @return [Array<DisplayableIdentity>]
      def resolve_by_identity_key(identity_key:, limit: nil, offset: nil)
        args = { identity_key: identity_key }
        args[:limit]  = limit  unless limit.nil?
        args[:offset] = offset unless offset.nil?

        result = @wallet.discover_by_identity_key(**args, originator: @originator)
        parse_certificates(result)
      end

      # Resolves displayable identities matching specific certificate attribute values.
      #
      # Delegates to the wallet's +discover_by_attributes+ and maps each
      # returned certificate through {IdentityParser.parse}.
      #
      # @param attributes [Hash] field name/value pairs to match
      # @param limit [Integer, nil] maximum number of certificates to return
      # @param offset [Integer, nil] number of certificates to skip
      # @return [Array<DisplayableIdentity>]
      def resolve_by_attributes(attributes:, limit: nil, offset: nil)
        args = { attributes: attributes }
        args[:limit]  = limit  unless limit.nil?
        args[:offset] = offset unless offset.nil?

        result = @wallet.discover_by_attributes(**args, originator: @originator)
        parse_certificates(result)
      end

      # Publicly reveals selected fields from a certificate by creating an
      # on-chain identity token and broadcasting it to the overlay network.
      #
      # The certificate is first optionally verified via the injected verifier,
      # then the wallet proves the selected fields to the "anyone" verifier
      # (PrivateKey(1) public key). A PushDrop locking script is constructed from
      # the certificate JSON plus keyring, and the resulting transaction is
      # broadcast to +tm_identity+.
      #
      # @param certificate [Hash] wallet certificate hash
      # @param fields_to_reveal [Array<String>] field names to include in the revelation
      # @return [BSV::Overlay::OverlayBroadcastResult]
      # @raise [ArgumentError] if the certificate has no fields or fields_to_reveal is empty
      # @raise [RuntimeError] if certificate verification fails or create_action returns no tx
      def publicly_reveal_attributes(certificate, fields_to_reveal:)
        fields = certificate[:fields] || certificate['fields'] || {}
        raise ArgumentError, 'Public reveal failed: Certificate has no fields to reveal!' if fields.empty?
        raise ArgumentError, 'Public reveal failed: You must reveal at least one field!' if fields_to_reveal.empty?

        verify_certificate(certificate)

        # Prove the certificate to the "anyone" verifier (PrivateKey(1) public key)
        anyone_pubkey = BSV::Script::PushDropTemplate::GENERATOR_PUBKEY_HEX
        prove_result  = @wallet.prove_certificate(
          certificate: certificate, fields_to_reveal: fields_to_reveal, verifier: anyone_pubkey,
          originator: @originator
        )
        keyring = prove_result[:keyring_for_verifier]

        # Build the PushDrop payload with ONLY the revealed fields — never
        # broadcast the full certificate (encrypted values for unrevealed
        # fields must not be written on-chain).
        revealed_fields = fields_to_reveal.to_h do |name|
          [name, fields[name.to_s] || fields[name.to_sym]]
        end

        serial_number = certificate[:serial_number] || certificate['serial_number'] ||
                        certificate[:serialNumber] || certificate['serialNumber']
        revocation_outpoint = certificate[:revocation_outpoint] || certificate['revocation_outpoint'] ||
                              certificate[:revocationOutpoint] || certificate['revocationOutpoint']

        payload = JSON.generate(
          type: certificate[:type] || certificate['type'],
          serialNumber: serial_number,
          subject: certificate[:subject] || certificate['subject'],
          certifier: certificate[:certifier] || certificate['certifier'],
          revocationOutpoint: revocation_outpoint,
          fields: revealed_fields,
          keyring: keyring
        )

        # Construct the locking script via PushDropTemplate
        template = BSV::Script::PushDropTemplate.new(wallet: @wallet, originator: @originator)
        locking_script = template.lock(
          fields: [payload],
          protocol_id: @options.protocol_id,
          key_id: @options.key_id,
          counterparty: 'anyone'
        )

        # Create the transaction
        create_result = @wallet.create_action(
          description: 'Create a new Identity Token',
          outputs: [
            {
              satoshis: @options.token_amount,
              locking_script: locking_script.to_hex,
              output_description: 'Identity Token'
            }
          ],
          options: { randomize_outputs: false },
          originator: @originator
        )

        raise 'Public reveal failed: failed to create action!' if create_result[:tx].nil?

        tx = BSV::Transaction::Tx.from_beef(create_result[:tx])
        broadcaster_for_action.broadcast(tx)
      end

      # Revokes a publicly revealed certificate by spending the identity token.
      #
      # Queries the +ls_identity+ lookup service for the revelation output identified
      # by +serial_number+, then creates a spending transaction via the wallet and
      # broadcasts it to +tm_identity+.
      #
      # @param serial_number [String] Base64 serial number of the certificate revelation to revoke
      # @return [void]
      # @raise [RuntimeError] if the revelation cannot be found or the transaction cannot be created
      def revoke_certificate_revelation(serial_number)
        question = BSV::Overlay::LookupQuestion.new(
          service: Constants::SERVICE,
          query: { serial_number: serial_number }
        )
        answer = resolver_for_action.query(question)

        raise 'Revoke failed: could not find revelation output' unless answer.type == 'output-list'
        raise 'Revoke failed: no outputs found for serial number' if answer.outputs.empty?

        output     = answer.outputs.first
        beef_bytes = output['beef'] || output[:beef]
        raise 'Revoke failed: overlay response missing BEEF data' unless beef_bytes

        raw_idx = output['outputIndex'] || output[:output_index]
        raise 'Revoke failed: overlay response missing outputIndex' if raw_idx.nil?

        output_idx = raw_idx.to_i
        raise 'Revoke failed: invalid outputIndex from overlay' if output_idx.negative?

        beef = BSV::Transaction::Beef.from_binary(beef_bytes)
        beef_tx = beef.transactions.last
        raise 'Revoke failed: no transaction found in BEEF' if beef_tx.nil? || beef_tx.is_a?(BSV::Transaction::Beef::TxidOnlyEntry)

        tx = beef_tx.transaction
        raise 'Revoke failed: outputIndex out of range' if output_idx >= tx.outputs.length

        # Overlay API boundary: outpoint uses display-order hex txid as per overlay convention
        txid = tx.txid_hex
        outpoint = "#{txid}.#{output_idx}"

        # Create a spending transaction; use unlocking_script_length so the wallet
        # produces a signable transaction that can then be signed and broadcast.
        create_result = @wallet.create_action(
          description: 'Spend certificate revelation token',
          input_beef: beef_bytes,
          inputs: [
            {
              input_description: 'Revelation token',
              outpoint: outpoint,
              unlocking_script_length: BSV::Script::PushDropTemplate::Unlocker::ESTIMATED_LENGTH
            }
          ],
          options: { randomize_outputs: false, no_send: true },
          originator: @originator
        )

        raise 'Revoke failed: failed to create signable transaction' if create_result[:signable_transaction].nil?

        signable = create_result[:signable_transaction]
        partial_tx = BSV::Transaction::Tx.from_beef(signable[:tx])

        # Unlock via PushDrop
        template = BSV::Script::PushDropTemplate.new(wallet: @wallet, originator: @originator)
        unlocker = template.unlock(
          protocol_id: @options.protocol_id,
          key_id: @options.key_id,
          counterparty: 'anyone'
        )
        # Sign the first (and only) input in the spending transaction.
        # output_idx is the index in the *source* tx; the spending tx input is always 0.
        spending_input_idx = 0
        unlocking_script = unlocker.sign(partial_tx, spending_input_idx)

        sign_result = @wallet.sign_action(
          reference: signable[:reference],
          spends: { spending_input_idx => { unlocking_script: unlocking_script.to_hex } },
          options: { no_send: true },
          originator: @originator
        )

        raise 'Revoke failed: failed to sign transaction' if sign_result[:tx].nil?

        signed_tx = BSV::Transaction::Tx.from_beef(sign_result[:tx])
        broadcaster_for_action.broadcast(signed_tx)
      end

      private

      # Maps an array of raw certificate hashes to DisplayableIdentity objects.
      #
      # Each certificate hash (as returned by the wallet's discovery methods) is
      # wrapped in an IdentityCertificate and parsed via IdentityParser.
      #
      # @param result [Hash, nil] wallet discovery result with :certificates key
      # @return [Array<DisplayableIdentity>]
      def parse_certificates(result)
        certs = result && result[:certificates]
        return [] if certs.nil? || certs.empty?

        certs.map { |cert| IdentityParser.parse(wrap_certificate(cert)) }
      end

      # Wraps a raw certificate hash in an IdentityCertificate, extracting
      # decrypted_fields and certifier_info where present.
      #
      # @param cert [Hash] raw certificate hash from the wallet
      # @return [IdentityCertificate]
      def wrap_certificate(cert)
        decrypted   = cert[:decrypted_fields] || cert['decrypted_fields'] || {}
        certifier_h = cert[:certifier_info]   || cert['certifier_info']   || {}

        certifier_info = if certifier_h && !certifier_h.empty?
                           CertifierInfo.new(
                             name: certifier_h[:name] || certifier_h['name'] || '',
                             icon_url: certifier_h[:icon_url] || certifier_h['icon_url']
                           )
                         end

        IdentityCertificate.new(
          certificate: cert,
          decrypted_fields: decrypted,
          certifier_info: certifier_info
        )
      end

      # Calls the injected certificate verifier, wrapping any errors in a
      # standardised RuntimeError message.
      #
      # @param certificate [Hash]
      # @raise [RuntimeError] if verification fails
      def verify_certificate(certificate)
        @certificate_verifier.call(certificate)
      rescue NotImplementedError
        raise
      rescue StandardError => e
        raise "Public reveal failed: Certificate verification failed! (#{e.message})"
      end

      # Returns the broadcaster to use for overlay actions, building one from
      # the wallet's network when no injectable broadcaster was provided.
      #
      # @return [BSV::Overlay::TopicBroadcaster]
      def broadcaster_for_action
        return @broadcaster if @broadcaster

        network = wallet_network
        BSV::Overlay::TopicBroadcaster.new(
          [Constants::TOPIC],
          network_preset: network
        )
      end

      # Returns the lookup resolver to use for overlay queries, building one from
      # the wallet's network when no injectable resolver was provided.
      #
      # @return [BSV::Overlay::LookupResolver]
      def resolver_for_action
        return @resolver if @resolver

        network = wallet_network
        BSV::Overlay::LookupResolver.new(network_preset: network)
      end

      # Queries the wallet for the current network and converts the string to a symbol.
      #
      # @return [Symbol] :mainnet or :testnet
      def wallet_network
        result = @wallet.get_network(originator: @originator)
        net_str = result[:network] || result['network'] || 'mainnet'
        net_str.to_sym
      end

      # Returns the default ClientOptions.
      #
      # @return [ClientOptions]
      def default_options
        ClientOptions::DEFAULT
      end
    end
  end
end
