# frozen_string_literal: true

module BSV
  module Wallet
    module Substrates
      # BRC-100 wallet Interface implementation that transmits calls over a binary wire transport.
      #
      # Serialises each Interface method call into a binary wire frame via
      # {BSV::Wallet::Wire::Serializer}, transmits it via a wire transport (any object
      # responding to `#transmit_to_wallet`), then deserialises the response.
      #
      # The wire transport is duck-typed — any object that accepts
      # `transmit_to_wallet(message)` where +message+ is an Array of byte integers
      # and returns an Array of byte integers qualifies. The canonical wire transport
      # is {HTTPWalletWire}.
      #
      # @example Using with HTTPWalletWire
      #   wire = BSV::Wallet::Substrates::HTTPWalletWire.new('http://localhost:3301')
      #   wallet = BSV::Wallet::Substrates::WalletWireTransceiver.new(wire, originator: 'myapp.example.com')
      #   result = wallet.get_public_key({ identity_key: true })
      #   # => { public_key: '02abc...' }
      class WalletWireTransceiver
        include BSV::Wallet::BRC100::Interface

        # @param wire [#transmit_to_wallet] wire transport (duck-typed)
        # @param originator [String, nil] default FQDN of the originating application;
        #   may be overridden per-call via the method-level originator keyword argument
        def initialize(wire, originator: nil)
          @wire = wire
          @originator = originator
        end

        def create_action(args, originator: nil)
          transmit(:create_action, args, originator || @originator)
        end

        def sign_action(args, originator: nil)
          transmit(:sign_action, args, originator || @originator)
        end

        def abort_action(args, originator: nil)
          transmit(:abort_action, args, originator || @originator)
        end

        def list_actions(args, originator: nil)
          transmit(:list_actions, args, originator || @originator)
        end

        def internalize_action(args, originator: nil)
          transmit(:internalize_action, args, originator || @originator)
        end

        def list_outputs(args, originator: nil)
          transmit(:list_outputs, args, originator || @originator)
        end

        def relinquish_output(args, originator: nil)
          transmit(:relinquish_output, args, originator || @originator)
        end

        def get_public_key(args, originator: nil)
          transmit(:get_public_key, args, originator || @originator)
        end

        def reveal_counterparty_key_linkage(args, originator: nil)
          transmit(:reveal_counterparty_key_linkage, args, originator || @originator)
        end

        def reveal_specific_key_linkage(args, originator: nil)
          transmit(:reveal_specific_key_linkage, args, originator || @originator)
        end

        def encrypt(args, originator: nil)
          transmit(:encrypt, args, originator || @originator)
        end

        def decrypt(args, originator: nil)
          transmit(:decrypt, args, originator || @originator)
        end

        def create_hmac(args, originator: nil)
          transmit(:create_hmac, args, originator || @originator)
        end

        def verify_hmac(args, originator: nil)
          transmit(:verify_hmac, args, originator || @originator)
        end

        def create_signature(args, originator: nil)
          transmit(:create_signature, args, originator || @originator)
        end

        def verify_signature(args, originator: nil)
          transmit(:verify_signature, args, originator || @originator)
        end

        def acquire_certificate(args, originator: nil)
          transmit(:acquire_certificate, args, originator || @originator)
        end

        def list_certificates(args, originator: nil)
          transmit(:list_certificates, args, originator || @originator)
        end

        def prove_certificate(args, originator: nil)
          transmit(:prove_certificate, args, originator || @originator)
        end

        def relinquish_certificate(args, originator: nil)
          transmit(:relinquish_certificate, args, originator || @originator)
        end

        def discover_by_identity_key(args, originator: nil)
          transmit(:discover_by_identity_key, args, originator || @originator)
        end

        def discover_by_attributes(args, originator: nil)
          transmit(:discover_by_attributes, args, originator || @originator)
        end

        def is_authenticated(args = {}, originator: nil)
          transmit(:is_authenticated, args, originator || @originator)
        end

        def wait_for_authentication(args = {}, originator: nil)
          transmit(:wait_for_authentication, args, originator || @originator)
        end

        def get_height(args = {}, originator: nil)
          transmit(:get_height, args, originator || @originator)
        end

        def get_header_for_height(args, originator: nil)
          transmit(:get_header_for_height, args, originator || @originator)
        end

        def get_network(args = {}, originator: nil)
          transmit(:get_network, args, originator || @originator)
        end

        def get_version(args = {}, originator: nil)
          transmit(:get_version, args, originator || @originator)
        end

        private

        # Serialises +method_name+ and +args+ into a binary wire frame, transmits it
        # via the wire transport, and deserialises the response.
        #
        # Error responses (non-zero first byte) are parsed and raised as {WalletError}
        # by {BSV::Wallet::Wire::Serializer.deserialize_response}.
        #
        # @param method_name [Symbol] BRC-100 method name (snake_case)
        # @param args [Hash] method arguments
        # @param orig [String, nil] FQDN of the originating application
        # @return [Hash] deserialised result
        def transmit(method_name, args, orig)
          frame = BSV::Wallet::Wire::Serializer.serialize_request(
            method_name, args || {}, originator: orig.to_s
          )
          response_bytes = @wire.transmit_to_wallet(frame.bytes.to_a)
          response_binary = response_bytes.pack('C*')
          BSV::Wallet::Wire::Serializer.deserialize_response(method_name, response_binary)
        end
      end
    end
  end
end
