# frozen_string_literal: true

require 'openssl'

module BSV
  module Primitives
    # BIP-32 hierarchical deterministic (HD) extended key.
    #
    # Supports both private and public extended keys, serialised as
    # Base58Check xprv/xpub strings. Provides child key derivation
    # (normal and hardened), path-based derivation (+m/44'/0'/0'+),
    # and neutering (private → public).
    #
    # @example Derive keys from a seed
    #   seed = SecureRandom.random_bytes(32)
    #   master = BSV::Primitives::ExtendedKey.from_seed(seed)
    #   child  = master.derive_path("m/44'/0'/0'/0/0")
    #   child.public_key.address #=> "1..."
    #
    # @example Parse an xpub string
    #   xpub = BSV::Primitives::ExtendedKey.from_string('xpub6...')
    #   xpub.public? #=> true
    class ExtendedKey
      # Offset added to child indices for hardened derivation.
      HARDENED = 0x80000000

      # Version bytes for extended key serialisation (BIP-32).
      VERSIONS = {
        mainnet_private: "\x04\x88\xAD\xE4".b,
        mainnet_public: "\x04\x88\xB2\x1E".b,
        testnet_private: "\x04\x35\x83\x94".b,
        testnet_public: "\x04\x35\x87\xCF".b
      }.freeze

      # Private extended key version bytes.
      PRIVATE_VERSIONS = [VERSIONS[:mainnet_private], VERSIONS[:testnet_private]].freeze

      # Public extended key version bytes.
      PUBLIC_VERSIONS  = [VERSIONS[:mainnet_public], VERSIONS[:testnet_public]].freeze

      # @return [String] raw key bytes (32-byte private or 33-byte compressed public)
      attr_reader :key

      # @return [String] 32-byte chain code for child derivation
      attr_reader :chain_code

      # @return [Integer] depth in the derivation tree (0 = master)
      attr_reader :depth

      # @return [String] 4-byte fingerprint of the parent key
      attr_reader :parent_fingerprint

      # @return [Integer] child number (index used to derive this key)
      attr_reader :child_number

      # @return [String] 4-byte version prefix
      attr_reader :version

      # @param key [String] raw key bytes
      # @param chain_code [String] 32-byte chain code
      # @param version [String] 4-byte version prefix
      # @param depth [Integer] derivation depth
      # @param parent_fingerprint [String] 4-byte parent fingerprint
      # @param child_number [Integer] child index
      def initialize(key:, chain_code:, version:, depth: 0, parent_fingerprint: "\x00\x00\x00\x00".b, child_number: 0)
        @key = key
        @chain_code = chain_code
        @depth = depth
        @parent_fingerprint = parent_fingerprint
        @child_number = child_number
        @version = version
      end

      # Derive a master extended key from a binary seed.
      #
      # Uses HMAC-SHA-512 with key +"Bitcoin seed"+ per BIP-32.
      #
      # @param seed [String] 16-64 byte seed (typically from {Mnemonic#to_seed})
      # @param network [Symbol] +:mainnet+ or +:testnet+
      # @return [ExtendedKey] the master private extended key
      # @raise [ArgumentError] if the seed length is invalid or derives an invalid key
      def self.from_seed(seed, network: :mainnet)
        seed = seed.b
        raise ArgumentError, 'seed must be between 16 and 64 bytes' unless seed.length.between?(16, 64)

        hmac = Digest.hmac_sha512('Bitcoin seed', seed)
        il = hmac[0, 32]
        ir = hmac[32, 32]

        il_bn = OpenSSL::BN.new(il, 2)
        raise ArgumentError, 'invalid seed: derived key is zero or >= curve order' if il_bn.zero? || il_bn >= Curve::N

        new(
          key: il,
          chain_code: ir,
          version: VERSIONS[:"#{network}_private"]
        )
      end

      # Parse an extended key from a Base58Check-encoded string (xprv/xpub).
      #
      # @param base58 [String] Base58Check-encoded extended key
      # @return [ExtendedKey]
      # @raise [ArgumentError] if the encoding, length, or version/key mismatch is invalid
      def self.from_string(base58)
        data = Base58.check_decode(base58)
        raise ArgumentError, "invalid extended key length: #{data.length}" unless data.length == 78

        version = data[0, 4]
        depth = data[4].unpack1('C')
        parent_fingerprint = data[5, 4]
        child_number = data[9, 4].unpack1('N')
        chain_code = data[13, 32]
        key_data = data[45, 33]

        if key_data[0] == "\x00".b
          raise ArgumentError, 'private key data with public version bytes' unless PRIVATE_VERSIONS.include?(version)

          key = key_data[1, 32]
        elsif ["\x02".b, "\x03".b].include?(key_data[0])
          raise ArgumentError, 'public key data with private version bytes' unless PUBLIC_VERSIONS.include?(version)

          key = key_data
        else
          raise ArgumentError, "invalid key data prefix: 0x#{key_data[0].unpack1('H*')}"
        end

        new(
          key: key,
          chain_code: chain_code,
          version: version,
          depth: depth,
          parent_fingerprint: parent_fingerprint,
          child_number: child_number
        )
      end

      # Whether this is a private extended key.
      #
      # @return [Boolean]
      def private?
        PRIVATE_VERSIONS.include?(@version)
      end

      # Whether this is a public extended key.
      #
      # @return [Boolean]
      def public?
        PUBLIC_VERSIONS.include?(@version)
      end

      # Derive a child key at the given index.
      #
      # Indices below {HARDENED} produce normal (public-derivable) children.
      # Indices >= {HARDENED} produce hardened children (private key required).
      #
      # @param index [Integer] the child index (use +HARDENED + n+ for hardened)
      # @return [ExtendedKey] the derived child key
      # @raise [ArgumentError] if deriving hardened from a public key, or at max depth
      def child(index)
        raise ArgumentError, 'cannot derive child at depth 255' if @depth >= 255

        if index >= HARDENED
          raise ArgumentError, 'cannot derive hardened child from public key' if public?

          data = "\x00".b + padded_key + [index].pack('N')
        else
          data = compressed_pubkey_bytes + [index].pack('N')
        end

        hmac = Digest.hmac_sha512(@chain_code, data)
        il = hmac[0, 32]
        ir = hmac[32, 32]

        il_bn = OpenSSL::BN.new(il, 2)
        raise ArgumentError, 'invalid child: IL >= curve order' if il_bn >= Curve::N

        fp = fingerprint

        child_key_bytes = if private?
                            child_key_bn = il_bn.mod_add(OpenSSL::BN.new(@key, 2), Curve::N)
                            raise ArgumentError, 'invalid child: derived key is zero' if child_key_bn.zero?

                            bn_to_32bytes(child_key_bn)
                          else
                            parent_point = Curve.point_from_bytes(@key)
                            il_point = Curve.multiply_generator_ct(il_bn)
                            child_point = Curve.add_points(parent_point, il_point)
                            raise ArgumentError, 'invalid child: derived point is at infinity' if child_point.infinity?

                            child_point.to_octet_string(:compressed)
                          end

        self.class.new(
          key: child_key_bytes,
          chain_code: ir,
          version: @version,
          depth: @depth + 1,
          parent_fingerprint: fp,
          child_number: index
        )
      end

      # Derive a child key from a BIP-32 path string.
      #
      # @param path [String] derivation path (e.g. +"m/44'/0'/0'/0/0"+)
      # @return [ExtendedKey] the derived key
      # @raise [ArgumentError] if the path does not start with +'m'+
      def derive_path(path)
        components = path.strip.split('/')
        raise ArgumentError, "path must start with 'm'" unless components.first == 'm'

        components[1..].reduce(self) do |key, component|
          hardened = component.end_with?("'", 'H', 'h')
          numeric_part = component.delete("'Hh")
          raise ArgumentError, "invalid path component: '#{component}'" unless numeric_part.match?(/\A\d+\z/)

          index = numeric_part.to_i
          index += HARDENED if hardened
          key.child(index)
        end
      end

      # Convert a private extended key to its public counterpart.
      #
      # @return [ExtendedKey] the public extended key (xpub)
      # @raise [ArgumentError] if already a public key
      def neuter
        raise ArgumentError, 'already a public key' if public?

        pub_version = if @version == VERSIONS[:mainnet_private]
                        VERSIONS[:mainnet_public]
                      else
                        VERSIONS[:testnet_public]
                      end

        self.class.new(
          key: compressed_pubkey_bytes,
          chain_code: @chain_code,
          version: pub_version,
          depth: @depth,
          parent_fingerprint: @parent_fingerprint,
          child_number: @child_number
        )
      end

      # Serialise as a Base58Check-encoded string (xprv or xpub).
      #
      # @return [String] the Base58Check-encoded extended key
      def to_s
        key_data = private? ? "\x00".b + padded_key : @key

        payload = @version +
                  [@depth].pack('C') +
                  @parent_fingerprint +
                  [@child_number].pack('N') +
                  @chain_code +
                  key_data

        Base58.check_encode(payload)
      end

      # Extract the {PrivateKey} from a private extended key.
      #
      # @return [PrivateKey]
      # @raise [ArgumentError] if this is a public extended key
      def private_key
        raise ArgumentError, 'not a private extended key' unless private?

        PrivateKey.from_bytes(padded_key)
      end

      # Extract the {PublicKey} from this extended key.
      #
      # @return [PublicKey]
      def public_key
        PublicKey.from_bytes(compressed_pubkey_bytes)
      end

      # The 4-byte fingerprint of this key (first 4 bytes of identifier).
      #
      # @return [String] 4-byte fingerprint
      def fingerprint
        identifier[0, 4]
      end

      # The 20-byte Hash160 identifier for this key.
      #
      # @return [String] 20-byte Hash160 of the compressed public key
      def identifier
        Digest.hash160(compressed_pubkey_bytes)
      end

      private

      def compressed_pubkey_bytes
        if private?
          bn = OpenSSL::BN.new(@key, 2)
          point = Curve.multiply_generator_ct(bn)
          point.to_octet_string(:compressed)
        else
          @key
        end
      end

      def padded_key
        raw = @key.b
        raw.length < 32 ? ("\x00".b * (32 - raw.length)) + raw : raw
      end

      def bn_to_32bytes(bn)
        raw = bn.to_s(2)
        raw.length < 32 ? ("\x00".b * (32 - raw.length)) + raw : raw
      end
    end
  end
end
