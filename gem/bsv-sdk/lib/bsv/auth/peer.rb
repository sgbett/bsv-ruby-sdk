# frozen_string_literal: true

require 'base64'
require 'json'

module BSV
  module Auth
    # BRC-31/BRC-103 mutual authentication peer.
    #
    # Manages the cryptographic handshake between two parties:
    #
    # 1. Alice calls {#initiate_handshake} — sends +initialRequest+ with her
    #    session nonce and requested certificates.
    # 2. Bob calls {#handle_incoming_message} — processes the request, creates
    #    his own session nonce, signs +decode(alice_nonce) + decode(bob_nonce)+,
    #    and sends +initialResponse+.
    # 3. Alice processes +initialResponse+ — verifies the nonce is hers
    #    (via HMAC), verifies Bob's signature, and marks the session authenticated.
    # 4. Both parties may now exchange authenticated +general+ messages.
    #
    # Sessions are indexed by +session_nonce+ (our nonce), which is the primary
    # key in the {SessionManager}.
    #
    # @example Using Peer with a custom transport
    #   wallet_a = BSV::Wallet::ProtoWallet.new(BSV::Primitives::PrivateKey.generate)
    #   wallet_b = BSV::Wallet::ProtoWallet.new(BSV::Primitives::PrivateKey.generate)
    #
    #   # Wire the two peers together with synchronous in-process transports
    #   peer_a = BSV::Auth::Peer.new(wallet: wallet_a)
    #   peer_b = BSV::Auth::Peer.new(wallet: wallet_b)
    #
    #   # Alice initiates; Bob responds; Alice completes
    #   request  = peer_a.create_initial_request
    #   response = peer_b.handle_incoming_message(request)
    #   peer_a.handle_incoming_message(response)
    class Peer
      AUTH_PROTOCOL = [2, 'auth message signature'].freeze

      attr_reader :wallet, :session_manager, :last_interacted_peer

      # @param wallet [BSV::Wallet::Interface] wallet providing crypto operations
      # @param transport [Transport, nil] optional transport for async usage
      # @param session_manager [SessionManager, nil] optional custom session store
      # @param certificates_to_request [Hash, nil] certificate set to request from peers
      # @param auto_persist_last_session [Boolean] whether to track the last-interacted peer (default: true)
      def initialize(wallet:, transport: nil, session_manager: nil, certificates_to_request: nil,
                     auto_persist_last_session: true)
        @wallet                    = wallet
        @transport                 = transport
        @session_manager           = session_manager || SessionManager.new
        @certificates_to_request   = certificates_to_request || { certifiers: [], types: {} }
        @identity_public_key       = nil
        @callbacks                 = { general_message: {}, certificates_received: {}, certificate_request: {} }
        @callback_id_counter       = 0
        @callback_mutex            = Mutex.new
        @last_interacted_peer      = nil
        @auto_persist_last_session = auto_persist_last_session

        return unless @transport

        @transport.on_data { |msg| handle_incoming_message(msg) }
      end

      # Registers a callback to be called when a general message is received.
      #
      # @yield [sender_key, payload] called with the sender's identity key and payload bytes
      # @return [Integer] callback ID (pass to {#off_general_message} to deregister)
      def on_general_message(&block)
        register_callback(:general_message, block)
      end

      # Removes a general message callback.
      #
      # @param callback_id [Integer] the ID returned by {#on_general_message}
      def off_general_message(callback_id)
        unregister_callback(:general_message, callback_id)
      end

      # Registers a callback to be called when certificates are received from a peer.
      #
      # @yield [sender_key, certs] called with sender's identity key and certificate array
      # @return [Integer] callback ID (pass to {#off_certificates_received} to deregister)
      def on_certificates_received(&block)
        register_callback(:certificates_received, block)
      end

      # Removes a certificates received callback.
      #
      # @param callback_id [Integer] the ID returned by {#on_certificates_received}
      def off_certificates_received(callback_id)
        unregister_callback(:certificates_received, callback_id)
      end

      # Registers a callback to be called when a certificate request is received from a peer.
      #
      # @yield [sender_key, requested_certs] called with sender's identity key and requested cert set
      # @return [Integer] callback ID (pass to {#off_certificate_request} to deregister)
      def on_certificate_request(&block)
        register_callback(:certificate_request, block)
      end

      # Removes a certificate request callback.
      #
      # @param callback_id [Integer] the ID returned by {#on_certificate_request}
      def off_certificate_request(callback_id)
        unregister_callback(:certificate_request, callback_id)
      end

      # Returns our identity key (cached after first call).
      #
      # @return [String] compressed public key hex
      def identity_key
        @identity_key ||= @wallet.get_public_key({ identity_key: true })[:public_key]
      end

      # Checks whether we have an authenticated session with a peer.
      #
      # Accepts either a +session_nonce+ or +peer_identity_key+.
      #
      # @param identifier [String]
      # @return [Boolean]
      def authenticated?(identifier)
        session = @session_manager.get_session(identifier)
        session&.authenticated? || false
      end

      # --- Handshake initiation (we are the initiator) ---

      # Builds an +initialRequest+ message and creates a pending session.
      #
      # @return [Hash] the message to send to the peer
      def create_initial_request
        session_nonce = Nonce.create(@wallet)

        session = PeerSession.new(session_nonce: session_nonce)
        session.certificates_required  = certifiers_present?
        session.certificates_validated = !session.certificates_required

        @session_manager.add_session(session)

        {
          version: AUTH_VERSION,
          message_type: MSG_INITIAL_REQUEST,
          identity_key: identity_key,
          initial_nonce: session_nonce,
          requested_certificates: @certificates_to_request
        }
      end

      # --- Incoming message dispatch ---

      # Processes any incoming auth message and returns a response (if applicable).
      #
      # When a transport is configured, any response is also forwarded via
      # +@transport.send+ so that the bidirectional flow works without the
      # caller having to manually route the return value.
      #
      # @param message [Hash] the incoming auth message
      # @return [Hash, nil] response message, or nil for messages requiring no reply
      # @raise [AuthError] if the version is wrong or the message type is unknown
      def handle_incoming_message(message)
        version = message[:version] || message['version']
        raise AuthError, "Unsupported auth version: #{version.inspect} (expected #{AUTH_VERSION})" unless version == AUTH_VERSION

        type = message[:message_type] || message['message_type']

        response = case type
                   when MSG_INITIAL_REQUEST  then process_initial_request(message)
                   when MSG_INITIAL_RESPONSE then process_initial_response(message)
                   when MSG_CERT_REQUEST     then process_certificate_request(message)
                   when MSG_CERT_RESPONSE    then process_certificate_response(message)
                   when MSG_GENERAL          then process_general_message(message)
                   else
                     raise AuthError, "Unknown message type: #{type.inspect}"
                   end

        # Only forward protocol messages (those with a message_type) back via
        # transport. Internal result hashes (e.g. from process_general_message)
        # carry no message_type and must not be forwarded.
        @transport&.send(response) if response&.key?(:message_type)
        response
      end

      # --- Certificate request/response (manual mode) ---

      # Builds a +certificateRequest+ message directed at an already-authenticated peer.
      #
      # @param peer_identifier [String] peer's session nonce or identity key
      # @param certificates_to_request [Hash] certifiers and types to request
      # @return [Hash] the message to send
      # @raise [AuthError] if not authenticated with this peer
      def create_certificate_request(peer_identifier, certificates_to_request)
        session = @session_manager.get_session(peer_identifier)
        raise AuthError, "Not authenticated with peer #{peer_identifier.inspect}" unless session&.authenticated?

        request_nonce = ::Base64.strict_encode64(SecureRandom.random_bytes(32))
        key_id        = key_id_for(request_nonce, session.peer_nonce)
        data          = JSON.generate(certificates_to_request).encode('UTF-8').bytes

        sig_result = @wallet.create_signature({
                                                data: data,
                                                protocol_id: AUTH_PROTOCOL,
                                                key_id: key_id,
                                                counterparty: session.peer_identity_key
                                              })

        session.last_update = current_time_ms
        @session_manager.update_session(session)

        {
          version: AUTH_VERSION,
          message_type: MSG_CERT_REQUEST,
          identity_key: identity_key,
          nonce: request_nonce,
          initial_nonce: session.session_nonce,
          your_nonce: session.peer_nonce,
          requested_certificates: certificates_to_request,
          signature: sig_result[:signature]
        }
      end

      # Builds a +certificateResponse+ message with the provided certificates.
      #
      # @param peer_identifier [String] peer's session nonce or identity key
      # @param certificates [Array<VerifiableCertificate, Hash>] certificates to send
      # @return [Hash] the message to send
      # @raise [AuthError] if not authenticated with this peer
      def create_certificate_response(peer_identifier, certificates)
        session = @session_manager.get_session(peer_identifier)
        raise AuthError, "Not authenticated with peer #{peer_identifier.inspect}" unless session&.authenticated?

        request_nonce = ::Base64.strict_encode64(SecureRandom.random_bytes(32))
        key_id        = key_id_for(request_nonce, session.peer_nonce)
        cert_data     = certificates.map { |c| c.respond_to?(:to_h) ? c.to_h : c }
        data          = JSON.generate(cert_data).encode('UTF-8').bytes

        sig_result = @wallet.create_signature({
                                                data: data,
                                                protocol_id: AUTH_PROTOCOL,
                                                key_id: key_id,
                                                counterparty: session.peer_identity_key
                                              })

        session.last_update = current_time_ms
        @session_manager.update_session(session)

        {
          version: AUTH_VERSION,
          message_type: MSG_CERT_RESPONSE,
          identity_key: identity_key,
          nonce: request_nonce,
          initial_nonce: session.session_nonce,
          your_nonce: session.peer_nonce,
          certificates: cert_data,
          signature: sig_result[:signature]
        }
      end

      # --- General message exchange (post-handshake) ---

      # Creates an authenticated +general+ message to send to a peer.
      #
      # @param peer_identifier [String] peer's session nonce or identity key
      # @param payload [Array<Integer>] byte array payload
      # @return [Hash] the message to send
      # @raise [AuthError] if not authenticated with this peer
      def create_general_message(peer_identifier, payload)
        session = @session_manager.get_session(peer_identifier)
        raise AuthError, "Not authenticated with peer #{peer_identifier.inspect}" unless session&.authenticated?

        # The receiver verifies `your_nonce` using their own wallet — so it must
        # be the peer's nonce (the nonce THEY created during the handshake).
        request_nonce = ::Base64.strict_encode64(SecureRandom.random_bytes(32))
        key_id        = key_id_for(request_nonce, session.peer_nonce)

        sig_result = @wallet.create_signature({
                                                data: payload,
                                                protocol_id: AUTH_PROTOCOL,
                                                key_id: key_id,
                                                counterparty: session.peer_identity_key
                                              })

        session.last_update = current_time_ms
        @session_manager.update_session(session)

        {
          version: AUTH_VERSION,
          message_type: MSG_GENERAL,
          identity_key: identity_key,
          nonce: request_nonce,
          your_nonce: session.peer_nonce,
          payload: payload,
          signature: sig_result[:signature]
        }
      end

      private

      # --- Processing: initial request (we are the responder) ---

      def process_initial_request(message)
        peer_key        = fetch!(message, :identity_key)
        their_nonce     = fetch!(message, :initial_nonce)

        raise AuthError, 'initial_nonce must not be empty' if their_nonce.empty?

        our_nonce = Nonce.create(@wallet)

        session                        = PeerSession.new(session_nonce: our_nonce)
        session.peer_identity_key      = peer_key
        session.peer_nonce             = their_nonce
        session.is_authenticated       = true
        session.certificates_required  = certifiers_present?
        session.certificates_validated = !session.certificates_required
        session.last_update            = current_time_ms

        @session_manager.add_session(session)

        # Handle the peer's certificate request (if any)
        certificates_to_include = handle_certificate_request_from_peer(message, peer_key)

        # Sign decode(their_nonce) + decode(our_nonce)
        # Key ID: "their_nonce our_nonce"  (initiator_nonce responder_nonce)
        sig_data = b64_decode(their_nonce) + b64_decode(our_nonce)
        key_id   = key_id_for(their_nonce, our_nonce)

        sig_result = @wallet.create_signature({
                                                data: sig_data,
                                                protocol_id: AUTH_PROTOCOL,
                                                key_id: key_id,
                                                counterparty: peer_key
                                              })

        @last_interacted_peer ||= peer_key if @auto_persist_last_session

        response = {
          version: AUTH_VERSION,
          message_type: MSG_INITIAL_RESPONSE,
          identity_key: identity_key,
          initial_nonce: our_nonce,
          your_nonce: their_nonce,
          requested_certificates: @certificates_to_request,
          signature: sig_result[:signature]
        }

        response[:certificates] = certificates_to_include if certificates_to_include

        response
      end

      # --- Processing: initial response (we are the initiator) ---

      def process_initial_response(message)
        their_nonce = fetch!(message, :initial_nonce)  # responder's nonce
        our_nonce   = fetch!(message, :your_nonce)     # our nonce echoed back
        peer_key    = fetch!(message, :identity_key)
        signature   = fetch!(message, :signature)

        # Verify the echoed nonce is one we created
        raise AuthError, "Nonce verification failed from peer: #{peer_key}" unless Nonce.verify(our_nonce, @wallet)

        session = @session_manager.get_session(our_nonce)
        raise AuthError, "No pending session for nonce: #{our_nonce.inspect}" unless session

        # Verify responder's signature over decode(our_nonce) + decode(their_nonce)
        # Key ID: "our_nonce their_nonce"  (initiator_nonce responder_nonce)
        sig_data = b64_decode(our_nonce) + b64_decode(their_nonce)
        key_id   = key_id_for(our_nonce, their_nonce)

        @wallet.verify_signature({
                                   data: sig_data,
                                   signature: signature,
                                   protocol_id: AUTH_PROTOCOL,
                                   key_id: key_id,
                                   counterparty: peer_key
                                 })

        # Authentication complete
        session.peer_nonce        = their_nonce
        session.peer_identity_key = peer_key
        session.is_authenticated  = true
        session.certificates_required  = certifiers_present?
        session.certificates_validated = !session.certificates_required
        session.last_update = current_time_ms

        @session_manager.update_session(session)

        @last_interacted_peer = peer_key if @auto_persist_last_session

        # Validate certificates if the responder included them
        resp_certs = message[:certificates] || message['certificates']
        if session.certificates_required && resp_certs.is_a?(Array) && !resp_certs.empty?
          validation_msg = { identity_key: peer_key, certificates: resp_certs }
          BSV::Auth.validate_certificates(@wallet, validation_msg, @certificates_to_request)
          session.certificates_validated = true
          session.last_update = current_time_ms
          @session_manager.update_session(session)
          fire_callbacks(:certificates_received, peer_key, resp_certs)
        end

        # Handle the responder's certificate request (if any)
        requested = message[:requested_certificates] || message['requested_certificates']
        if certifiers_present_in?(requested)
          if callbacks_registered?(:certificate_request)
            fire_callbacks(:certificate_request, peer_key, requested)
          else
            certs = BSV::Auth.get_verifiable_certificates(@wallet, requested, peer_key)
            if certs.length.positive?
              cert_response = create_certificate_response(peer_key, certs)
              @transport&.send(cert_response)
            end
          end
        end

        nil
      rescue BSV::Wallet::InvalidSignatureError
        @session_manager.remove_session(session) if session
        raise AuthError, "Initial response signature verification failed from peer: #{peer_key}"
      end

      # --- Processing: general message (we are the receiver) ---

      def process_general_message(message)
        our_nonce = fetch!(message, :your_nonce) # our session nonce echoed back
        peer_key  = fetch!(message, :identity_key)
        payload   = message[:payload] || message['payload'] || []
        signature = fetch!(message, :signature)
        msg_nonce = fetch!(message, :nonce)

        # Verify the echoed nonce is one we created
        raise AuthError, "Unable to verify nonce for general message from: #{peer_key}" unless Nonce.verify(our_nonce, @wallet)

        session = @session_manager.get_session(our_nonce)
        raise AuthError, "Session not found for nonce: #{our_nonce.inspect}" unless session

        # Verify signature: signed over payload with key_id "msg_nonce session_nonce"
        key_id = key_id_for(msg_nonce, session.session_nonce)

        @wallet.verify_signature({
                                   data: payload,
                                   signature: signature,
                                   protocol_id: AUTH_PROTOCOL,
                                   key_id: key_id,
                                   counterparty: session.peer_identity_key
                                 })

        session.last_update = current_time_ms
        @session_manager.update_session(session)

        @last_interacted_peer = session.peer_identity_key if @auto_persist_last_session
        fire_callbacks(:general_message, session.peer_identity_key, payload)

        { peer_identity_key: session.peer_identity_key, payload: payload }
      rescue BSV::Wallet::InvalidSignatureError
        raise AuthError, "General message signature verification failed from: #{peer_key}"
      end

      # --- Processing: certificate request (we are the responder) ---

      def process_certificate_request(message)
        our_nonce = fetch!(message, :your_nonce)
        peer_key  = message[:identity_key] || message['identity_key']
        msg_nonce = fetch!(message, :nonce)
        requested = message[:requested_certificates] || message['requested_certificates']
        signature = fetch!(message, :signature)

        raise AuthError, "Unable to verify nonce for certificate request message from: #{peer_key}" unless Nonce.verify(our_nonce, @wallet)

        session = @session_manager.get_session(our_nonce)
        raise AuthError, "Session not found for nonce: #{our_nonce.inspect}" unless session

        data   = JSON.generate(requested).encode('UTF-8').bytes
        key_id = key_id_for(msg_nonce, session.session_nonce)

        @wallet.verify_signature({
                                   data: data,
                                   signature: signature,
                                   protocol_id: AUTH_PROTOCOL,
                                   key_id: key_id,
                                   counterparty: session.peer_identity_key
                                 })

        session.last_update = current_time_ms
        @session_manager.update_session(session)

        return unless certifiers_present_in?(requested)

        if callbacks_registered?(:certificate_request)
          fire_callbacks(:certificate_request, session.peer_identity_key, requested)
        else
          certs = BSV::Auth.get_verifiable_certificates(@wallet, requested, session.peer_identity_key)
          if certs.length.positive?
            cert_response = create_certificate_response(session.peer_identity_key, certs)
            @transport&.send(cert_response)
          end
        end

        nil
      rescue BSV::Wallet::InvalidSignatureError
        raise AuthError, "Certificate request signature verification failed from: #{peer_key}"
      end

      # --- Processing: certificate response (we are the initiator or requester) ---

      def process_certificate_response(message)
        our_nonce = fetch!(message, :your_nonce)
        peer_key  = message[:identity_key] || message['identity_key']
        msg_nonce = fetch!(message, :nonce)
        certs     = message[:certificates] || message['certificates'] || []
        signature = fetch!(message, :signature)

        raise AuthError, "Unable to verify nonce for certificate response from: #{peer_key}" unless Nonce.verify(our_nonce, @wallet)

        session = @session_manager.get_session(our_nonce)
        raise AuthError, "Session not found for nonce: #{our_nonce.inspect}" unless session

        data   = JSON.generate(certs).encode('UTF-8').bytes
        key_id = key_id_for(msg_nonce, session.session_nonce)

        @wallet.verify_signature({
                                   data: data,
                                   signature: signature,
                                   protocol_id: AUTH_PROTOCOL,
                                   key_id: key_id,
                                   counterparty: session.peer_identity_key
                                 })

        if certs.is_a?(Array) && !certs.empty?
          validation_msg = { identity_key: session.peer_identity_key, certificates: certs }
          BSV::Auth.validate_certificates(@wallet, validation_msg)
          session.certificates_validated = true
          session.last_update = current_time_ms
          @session_manager.update_session(session)
        end

        fire_callbacks(:certificates_received, session.peer_identity_key, certs)

        nil
      rescue BSV::Wallet::InvalidSignatureError
        raise AuthError, "Certificate response signature verification failed from: #{peer_key}"
      end

      # --- Callback helpers ---

      def register_callback(type, block)
        @callback_mutex.synchronize do
          id = @callback_id_counter += 1
          @callbacks[type][id] = block
          id
        end
      end

      def unregister_callback(type, callback_id)
        @callback_mutex.synchronize { @callbacks[type].delete(callback_id) }
      end

      # Dup the hash under the mutex, then iterate outside to avoid re-entrancy
      # deadlocks (a callback may call back into Peer, e.g. via PairedTransport).
      def fire_callbacks(type, *args)
        callbacks = @callback_mutex.synchronize { @callbacks[type].dup }
        callbacks.each_value { |cb| cb.call(*args) }
      end

      # --- Helpers ---

      # Builds the key ID string: "prefix suffix".
      # @param prefix [String] first nonce (base64)
      # @param suffix [String] second nonce (base64)
      # @return [String]
      def key_id_for(prefix, suffix)
        "#{prefix} #{suffix}"
      end

      # Decodes a base64 string to a byte array (Array<Integer>).
      # @param b64 [String]
      # @return [Array<Integer>]
      def b64_decode(b64)
        ::Base64.strict_decode64(b64).bytes
      end

      # Fetches a value from a message hash, trying both Symbol and String keys.
      # @param message [Hash]
      # @param key [Symbol]
      # @return [Object]
      # @raise [AuthError] if the key is missing or nil
      def fetch!(message, key)
        value = message[key] || message[key.to_s]
        raise AuthError, "Missing required field: #{key}" if value.nil?
        raise AuthError, "Field #{key} must not be empty" if value.respond_to?(:empty?) && value.empty?

        value
      end

      def certifiers_present?
        certs = @certificates_to_request[:certifiers] || @certificates_to_request['certifiers']
        certs.is_a?(Array) && !certs.empty?
      end

      # Returns true if the given requested_certificates hash has at least one certifier.
      def certifiers_present_in?(requested)
        return false unless requested.is_a?(Hash)

        certifiers = requested[:certifiers] || requested['certifiers']
        certifiers.is_a?(Array) && !certifiers.empty?
      end

      # Returns true if at least one callback of the given type is registered.
      def callbacks_registered?(type)
        @callback_mutex.synchronize { @callbacks[type].any? }
      end

      # Handles a peer's certificate request embedded in an initialRequest message.
      #
      # If callbacks are registered, fires them and returns nil (caller adds no certs).
      # Otherwise, auto-fetches certificates and returns the serialised array (or nil if empty).
      #
      # @param message [Hash] the initialRequest message
      # @param peer_key [String] the peer's identity key
      # @return [Array<Hash>, nil] serialised certificates to include, or nil
      def handle_certificate_request_from_peer(message, peer_key)
        requested = message[:requested_certificates] || message['requested_certificates']
        return nil unless certifiers_present_in?(requested)

        if callbacks_registered?(:certificate_request)
          fire_callbacks(:certificate_request, peer_key, requested)
          return nil
        end

        certs = BSV::Auth.get_verifiable_certificates(@wallet, requested, peer_key)
        return nil if certs.empty?

        certs.map { |c| c.respond_to?(:to_h) ? c.to_h : c }
      end

      def current_time_ms
        (Time.now.to_f * 1000).to_i
      end
    end
  end
end
