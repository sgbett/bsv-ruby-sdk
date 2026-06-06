# frozen_string_literal: true

module BSV
  module Transaction
    # P2PKH unlocking script template for deferred transaction signing.
    #
    # Holds a private key and sighash type, generating the unlocking script
    # (signature + public key) when {#sign} is called with the full transaction.
    #
    # @example Attach a P2PKH template to an input
    #   input.unlocking_script_template = BSV::Transaction::P2PKH.new(private_key)
    #   tx.sign_all  # generates the unlocking script
    class P2PKH < UnlockingScriptTemplate
      # Estimated unlocking script length: 1 + ~72 (DER sig + hashtype) + 1 + 33 (compressed pubkey).
      ESTIMATED_SCRIPT_LENGTH = 107

      # @param private_key [Primitives::PrivateKey] the signing key
      # @param sighash_type [Integer] sighash flags (default: ALL_FORK_ID)
      def initialize(private_key, sighash_type: Sighash::ALL_FORK_ID)
        super()
        @private_key = private_key
        @sighash_type = sighash_type
      end

      # Generate the P2PKH unlocking script for the given input.
      #
      # @param tx [Tx] the transaction being signed
      # @param input_index [Integer] the input index to sign
      # @return [Script::Script] the unlocking script (signature + pubkey)
      def sign(tx, input_index)
        hash = tx.sighash(input_index, @sighash_type)
        signature = @private_key.sign(hash)
        sig_with_hashtype = signature.to_der + [@sighash_type].pack('C')
        pubkey_bytes = @private_key.public_key.compressed
        BSV::Script::Script.p2pkh_unlock(sig_with_hashtype, pubkey_bytes)
      end

      # @return [Integer] estimated script length for fee calculation
      def estimated_length(_tx, _input_index)
        ESTIMATED_SCRIPT_LENGTH
      end
    end
  end
end
