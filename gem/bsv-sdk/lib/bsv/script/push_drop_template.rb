# frozen_string_literal: true

module BSV
  module Script
    # Wallet-integrated PushDrop template for any protocol.
    #
    # Generalises the pattern used by {BSV::Overlay::AdminTokenTemplate} —
    # derives a locking key from the wallet, optionally signs the data fields,
    # and wraps everything in a PushDrop script backed by a P2PKH condition.
    #
    # == Note: P2PKH vs P2PK
    #
    # This template uses P2PKH as the underlying spending condition. The
    # {BSV::Overlay::AdminTokenTemplate} uses P2PK (matching the TS/Go SDKs'
    # overlay admin token convention). The two lock types are not
    # interchangeable — tokens locked by one cannot be unlocked by the other.
    #
    # PushDrop scripts embed arbitrary token data inline in a spendable output:
    #
    #   <field0> <field1> ... <fieldN> [OP_2DROP...] [OP_DROP?]
    #   OP_DUP OP_HASH160 <hash160(derived_pubkey)> OP_EQUALVERIFY OP_CHECKSIG
    #
    # When +include_signature: true+ (the default), an ECDSA signature over the
    # concatenation of all fields is appended as a final field. This
    # authenticates the token at creation time using the same derived key.
    #
    # == Security note: +counterparty: 'anyone'+ tokens
    #
    # When +counterparty+ is +'anyone'+, the locking key is derived from the
    # secp256k1 generator point G (PrivateKey(1)). This is a publicly known
    # scalar, meaning:
    #
    # 1. The output is **publicly spendable** — any party can sign with
    #    PrivateKey(1) and spend the token. This is by design for overlay
    #    tokens where public revocability is desired.
    # 2. The field signature (+include_signature: true+) provides **no
    #    authenticity guarantee** — anyone can produce a valid signature with
    #    the known key. Rely on higher-level mechanisms (e.g. certificate
    #    keyrings from +prove_certificate+) for field-level integrity.
    #
    # @example Lock a token
    #   wallet   = BSV::Wallet::Client.new(private_key, storage: BSV::Wallet::Store::Memory.new)
    #   template = BSV::Script::PushDropTemplate.new(wallet:)
    #   script   = template.lock(
    #     fields:       ['hello'.b, 'world'.b],
    #     protocol_id:  [1, 'my-protocol'],
    #     key_id:       '1',
    #     counterparty: 'self'
    #   )
    #   script.pushdrop? #=> true
    #
    # @example Unlock a token
    #   unlocker = template.unlock(
    #     protocol_id:  [1, 'my-protocol'],
    #     key_id:       '1',
    #     counterparty: 'self'
    #   )
    #   input.unlocking_script_template = unlocker
    class PushDropTemplate
      # Public key for PrivateKey(1) — the generator point G.
      # Used when +counterparty: 'anyone'+ so any party can verify.
      GENERATOR_PUBKEY_HEX =
        '0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798'

      # Unlocking template returned by {#unlock}.
      #
      # Satisfies the P2PKH condition embedded in a PushDrop locking script
      # by computing the BIP-143 sighash and signing it with the wallet's
      # derived key.
      class Unlocker
        # Estimated unlocking script length in bytes.
        #
        # P2PKH unlock is 1 + ~72 (DER sig + hashtype) + 1 + 33 (pubkey) = 107 bytes.
        # In PushDrop context the unlock wraps P2PKH, so the estimate is the same.
        ESTIMATED_LENGTH = 107

        # @param wallet [#create_signature, #get_public_key] BRC-100 wallet interface
        # @param protocol_id [Array] two-element [security_level, protocol_name]
        # @param key_id [String] key identifier
        # @param counterparty [String] 'self', 'anyone', or a hex public key
        # @param originator [String, nil] optional originator domain
        def initialize(wallet, protocol_id, key_id, counterparty, originator)
          @wallet = wallet
          @protocol_id = protocol_id
          @key_id = key_id
          @counterparty = counterparty
          @originator = originator
        end

        # Generate the unlocking script for the given input.
        #
        # Computes the BIP-143 sighash (SIGHASH_ALL|FORK_ID), signs it with
        # the wallet's derived key, then returns a P2PKH unlock wrapped in a
        # PushDrop unlock (which is a pass-through).
        #
        # @param tx [BSV::Transaction::Transaction] the spending transaction
        # @param input_index [Integer] which input to sign
        # @return [BSV::Script::Script] the unlocking script
        def sign(tx, input_index)
          sighash_type = BSV::Transaction::Sighash::ALL_FORK_ID
          hash = tx.sighash(input_index, sighash_type)
          hash_bytes = hash.unpack('C*')

          sig_args = {
            hash_to_directly_sign: hash_bytes,
            protocol_id: @protocol_id,
            key_id: @key_id,
            counterparty: @counterparty
          }
          result = @wallet.create_signature(**sig_args, **originator_kw)

          sig_bytes = result[:signature].pack('C*')
          sig_with_hashtype = sig_bytes + [sighash_type].pack('C')

          # Fetch the derived public key so the P2PKH unlock can include it
          pub_args = { protocol_id: @protocol_id, key_id: @key_id, counterparty: @counterparty }
          pub_result = @wallet.get_public_key(**pub_args, **originator_kw)
          pubkey_bytes = [pub_result[:public_key]].pack('H*')

          BSV::Script::Script.pushdrop_unlock(
            BSV::Script::Script.p2pkh_unlock(sig_with_hashtype, pubkey_bytes)
          )
        end

        # Estimated byte length of the unlocking script.
        #
        # @param _tx [BSV::Transaction::Transaction] unused
        # @param _input_index [Integer] unused
        # @return [Integer]
        def estimated_length(_tx, _input_index)
          ESTIMATED_LENGTH
        end

        private

        def originator_kw
          @originator ? { originator: @originator } : {}
        end
      end

      # @param wallet [#get_public_key, #create_signature] BRC-100 wallet interface
      # @param originator [String, nil] optional FQDN of the originating application
      def initialize(wallet:, originator: nil)
        @wallet = wallet
        @originator = originator
      end

      # Create a PushDrop locking script for the given data fields.
      #
      # Derives a public key from the wallet using the supplied protocol
      # parameters, then builds a P2PKH locking condition from it. When
      # +include_signature: true+ (the default), signs the concatenation of all
      # fields and appends the DER signature as an additional field.
      #
      # When +counterparty+ is +'anyone'+, the generator point (PrivateKey(1)
      # public key) is used directly as the locking key. This is the convention
      # for tokens that any party can verify.
      #
      # The +lock_position+ parameter controls where the P2PKH locking condition
      # is placed relative to the data fields. Defaults to +:before+ (lock first,
      # then fields and drops), matching the ts-sdk convention.
      #
      # **Breaking change (v0.9):** the default changed from +:after+ to +:before+.
      # Callers that relied on the old layout must pass +lock_position: :after+.
      #
      # @param fields [Array<String>] data payloads to embed (binary strings)
      # @param protocol_id [Array] two-element [security_level, protocol_name]
      # @param key_id [String] key identifier
      # @param counterparty [String] 'self', 'anyone', or a hex public key
      # @param include_signature [Boolean] whether to append an ECDSA field signature
      # @param lock_position [Symbol] +:before+ (default) or +:after+
      # @return [BSV::Script::Script] the PushDrop locking script
      # @raise [ArgumentError] if fields is empty
      def lock(fields:, protocol_id:, key_id:, counterparty:, include_signature: true, lock_position: :before)
        raise ArgumentError, 'fields must not be empty' if fields.empty?

        # When counterparty is 'anyone', use the generator point directly as the
        # locking key — this is the "anyone can verify" convention.
        pubkey_bytes = if counterparty == 'anyone'
                         [GENERATOR_PUBKEY_HEX].pack('H*')
                       else
                         pub_args = { protocol_id: protocol_id, key_id: key_id, counterparty: counterparty }
                         pub_result = @wallet.get_public_key(**pub_args, **originator_kw)
                         [pub_result[:public_key]].pack('H*')
                       end

        # Build all fields, optionally appending a signature over their concatenation
        all_fields = fields.map(&:b)

        if include_signature
          data_to_sign = all_fields.reduce(''.b) { |acc, f| acc + f }.unpack('C*')
          sig_args = { data: data_to_sign, protocol_id: protocol_id, key_id: key_id, counterparty: counterparty }
          sig_result = @wallet.create_signature(**sig_args, **originator_kw)
          all_fields << sig_result[:signature].pack('C*')
        end

        # Build P2PKH lock from the derived pubkey's Hash160
        pubkey_hash = BSV::Primitives::Digest.hash160(pubkey_bytes)
        p2pkh_lock = BSV::Script::Script.p2pkh_lock(pubkey_hash)

        BSV::Script::Script.pushdrop_lock(all_fields, p2pkh_lock, lock_position: lock_position)
      end

      # Return an unlocker for spending a PushDrop token output.
      #
      # The returned {Unlocker} follows the unlocking template interface and
      # can be assigned to an input's +unlocking_script_template+.
      #
      # @param protocol_id [Array] two-element [security_level, protocol_name]
      # @param key_id [String] key identifier
      # @param counterparty [String] 'self', 'anyone', or a hex public key
      # @return [Unlocker] object with +#sign+ and +#estimated_length+
      def unlock(protocol_id:, key_id:, counterparty:)
        Unlocker.new(@wallet, protocol_id, key_id, counterparty, @originator)
      end

      private

      def originator_kw
        @originator ? { originator: @originator } : {}
      end
    end
  end
end
