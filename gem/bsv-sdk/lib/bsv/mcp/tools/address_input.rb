# frozen_string_literal: true

module BSV
  module MCP
    module Tools
      # Validates address and WIF input for the tools that query an address,
      # before anything is sent over the network.
      module AddressInput
        ADDRESS_VERSIONS = { mainnet: "\x00".b, testnet: "\x6f".b }.freeze
        WIF_VERSIONS = { mainnet: "\x80".b, testnet: "\xef".b }.freeze
        private_constant :ADDRESS_VERSIONS, :WIF_VERSIONS

        # Resolve user input to a P2PKH address for +net_sym+, before anything
        # is sent over the network.
        #
        # The input is decoded as Base58Check: a P2PKH address for the network
        # is returned as is; with +allow_wif+, a WIF private key for the network
        # yields its address. Anything else (bad characters or checksum, P2SH,
        # the other network, wrong length) raises an error that never includes
        # the input, which may be a mistyped private key.
        #
        # @param input [String]
        # @param net_sym [Symbol] :mainnet or :testnet
        # @param allow_wif [Boolean] also accept a WIF private key
        # @return [String] the address
        # @raise [ArgumentError] with a fixed message
        def self.resolve(input, net_sym, allow_wif: false)
          payload = decode_base58check(input)
          address = payload && address_from_payload(payload, net_sym, allow_wif)
          return address if address

          accepted = allow_wif ? 'a P2PKH address or WIF private key' : 'a P2PKH address'
          raise ArgumentError, "input is not #{accepted} for #{net_sym}"
        end

        # @api private
        def self.decode_base58check(input)
          return unless input.is_a?(String)

          BSV::Primitives::Base58.check_decode(input)
        rescue StandardError
          nil
        end

        # @api private
        def self.address_from_payload(payload, net_sym, allow_wif)
          version = payload[0]
          body = payload[1..]
          return base58_address(payload) if version == ADDRESS_VERSIONS.fetch(net_sym) && body.bytesize == 20
          return unless allow_wif && version == WIF_VERSIONS.fetch(net_sym)

          key_bytes = wif_key_bytes(body)
          BSV::Primitives::PrivateKey.from_bytes(key_bytes).public_key.address(network: net_sym) if key_bytes
        rescue ArgumentError
          nil
        end

        # @api private
        def self.base58_address(payload)
          BSV::Primitives::Base58.check_encode(payload)
        end

        # The 32 key bytes of a WIF payload (uncompressed, or compressed with its flag).
        # @api private
        def self.wif_key_bytes(body)
          return body if body.bytesize == 32
          return body[0, 32] if body.bytesize == 33 && body[32] == "\x01".b

          nil
        end
      end
    end
  end
end
