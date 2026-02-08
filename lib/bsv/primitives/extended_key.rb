# frozen_string_literal: true

require 'openssl'

module BSV
  module Primitives
    class ExtendedKey
      HARDENED = 0x80000000

      VERSIONS = {
        mainnet_private: "\x04\x88\xAD\xE4".b,
        mainnet_public: "\x04\x88\xB2\x1E".b,
        testnet_private: "\x04\x35\x83\x94".b,
        testnet_public: "\x04\x35\x87\xCF".b
      }.freeze

      PRIVATE_VERSIONS = [VERSIONS[:mainnet_private], VERSIONS[:testnet_private]].freeze
      PUBLIC_VERSIONS  = [VERSIONS[:mainnet_public], VERSIONS[:testnet_public]].freeze

      attr_reader :key, :chain_code, :depth, :parent_fingerprint, :child_number, :version

      def initialize(key:, chain_code:, version:, depth: 0, parent_fingerprint: "\x00\x00\x00\x00".b,
                     child_number: 0)
        @key = key
        @chain_code = chain_code
        @depth = depth
        @parent_fingerprint = parent_fingerprint
        @child_number = child_number
        @version = version
      end

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

      def private?
        PRIVATE_VERSIONS.include?(@version)
      end

      def public?
        PUBLIC_VERSIONS.include?(@version)
      end

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
                            il_point = Curve.multiply_generator(il_bn)
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

      def derive_path(path)
        components = path.strip.split('/')
        raise ArgumentError, "path must start with 'm'" unless components.first == 'm'

        components[1..].reduce(self) do |key, component|
          hardened = component.end_with?("'", 'H', 'h')
          index = component.to_i
          index += HARDENED if hardened
          key.child(index)
        end
      end

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

      def private_key
        raise ArgumentError, 'not a private extended key' unless private?

        PrivateKey.from_bytes(padded_key)
      end

      def public_key
        PublicKey.from_bytes(compressed_pubkey_bytes)
      end

      def fingerprint
        identifier[0, 4]
      end

      def identifier
        Digest.hash160(compressed_pubkey_bytes)
      end

      private

      def compressed_pubkey_bytes
        if private?
          bn = OpenSSL::BN.new(@key, 2)
          point = Curve.multiply_generator(bn)
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
