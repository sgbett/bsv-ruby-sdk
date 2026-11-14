# frozen_string_literal: true

module BSV
  module MCP
    module Tools
      # Validates address and WIF input for the tools that query an address or
      # pay one, before anything is sent over the network.
      module AddressInput
        ADDRESS_VERSIONS = {
          mainnet: BSV::Primitives::PublicKey::MAINNET_PUBKEY_HASH,
          testnet: BSV::Primitives::PublicKey::TESTNET_PUBKEY_HASH
        }.freeze
        WIF_VERSIONS = {
          mainnet: BSV::Primitives::PrivateKey::MAINNET_PREFIX,
          testnet: BSV::Primitives::PrivateKey::TESTNET_PREFIX
        }.freeze
        P2PKH_HASH_BYTES = 20
        private_constant :ADDRESS_VERSIONS, :WIF_VERSIONS, :P2PKH_HASH_BYTES

        # Addresses are at most 35 characters and WIFs 52. Base58 decoding is
        # quadratic, so anything much longer could stall the single-threaded
        # stdio server; the input schemas carry the same limit.
        MAX_LENGTH = 64

        # @param input [Object]
        # @param name [String] the argument's name, for the error message
        # @raise [ArgumentError] when a String input is over {MAX_LENGTH}; the
        #   message never includes the input
        def self.ensure_length!(input, name)
          return unless input.is_a?(String) && input.length > MAX_LENGTH

          raise ArgumentError, "#{name} is longer than #{MAX_LENGTH} characters"
        end

        # The 20-byte public key hash of a P2PKH address for +net_sym+, for
        # building a locking script. Callers must lock to this hash and never pass
        # the address string on: +Script.p2pkh_lock+ takes any 20-byte String as a
        # raw hash, so a 20-character malformed address would be locked to its own
        # ASCII bytes.
        #
        # The input is decoded as Base58Check and must carry the P2PKH version byte
        # for the network and a 20-byte payload. Anything else (bad characters or
        # checksum, P2SH, a WIF, the other network, wrong length, a non-String)
        # raises an error that never includes the input.
        #
        # @param input [Object]
        # @param net_sym [Symbol] :mainnet or :testnet
        # @param name [String] the argument's name, for the error message
        # @return [String] the frozen 20-byte binary hash
        # @raise [ArgumentError] with a fixed message
        def self.pubkey_hash(input, net_sym, name: 'input')
          ensure_length!(input, name)
          payload = decode_base58check(input)
          hash = payload && p2pkh_hash(payload, net_sym)
          return hash if hash

          raise ArgumentError, "#{name} is not a P2PKH address for #{net_sym}"
        end

        # The private key behind a WIF for +net_sym+, decoded the way addresses
        # are, so that a mistyped key is never echoed back: Base58's own error
        # names the first invalid character.
        #
        # @param wif [Object]
        # @param net_sym [Symbol] :mainnet or :testnet
        # @param name [String] the argument's name, for the error message
        # @return [BSV::Primitives::PrivateKey]
        # @raise [ArgumentError] with a fixed message, whether the WIF is invalid
        #   or belongs to the other network (so a testnet key never signs a
        #   mainnet spend, or the reverse)
        def self.private_key(wif, net_sym, name: 'wif')
          ensure_length!(wif, name)
          payload = decode_base58check(wif)
          key = payload && wif_private_key(payload)
          raise ArgumentError, "#{name} is not a valid WIF private key for #{net_sym}" unless key
          raise ArgumentError, "WIF private key is not for #{net_sym}" unless payload.byteslice(0, 1) == WIF_VERSIONS.fetch(net_sym)

          key
        end

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
        # @param name [String] the argument's name, for the error message
        # @return [String] the address
        # @raise [ArgumentError] with a fixed message
        def self.resolve(input, net_sym, allow_wif: false, name: 'input')
          ensure_length!(input, name)
          payload = decode_base58check(input)
          address = payload && address_from_payload(payload, net_sym, allow_wif)
          return address if address

          accepted = allow_wif ? 'a P2PKH address or WIF private key' : 'a P2PKH address'
          raise ArgumentError, "#{name} is not #{accepted} for #{net_sym}"
        end

        # @api private
        def self.decode_base58check(input)
          return unless input.is_a?(String)

          BSV::Primitives::Base58.check_decode(input)
        rescue StandardError
          nil
        end

        # The decoded payload is the version byte followed by the body.
        # @api private
        def self.address_from_payload(payload, net_sym, allow_wif)
          return base58_address(payload) if p2pkh_hash(payload, net_sym)
          return unless allow_wif && payload.byteslice(0, 1) == WIF_VERSIONS.fetch(net_sym)

          wif_private_key(payload)&.public_key&.address(network: net_sym)
        rescue ArgumentError
          nil
        end

        # The key of a WIF payload for either network.
        # @api private
        def self.wif_private_key(payload)
          return unless WIF_VERSIONS.value?(payload.byteslice(0, 1))

          key_bytes = wif_key_bytes(payload.byteslice(1..))
          BSV::Primitives::PrivateKey.from_bytes(key_bytes) if key_bytes
        rescue ArgumentError
          nil
        end

        # @return [String, nil] the frozen hash when the payload is a P2PKH one for the network
        # @api private
        def self.p2pkh_hash(payload, net_sym)
          return unless payload.byteslice(0, 1) == ADDRESS_VERSIONS.fetch(net_sym)

          body = payload.byteslice(1..)
          body.freeze if body.bytesize == P2PKH_HASH_BYTES
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
