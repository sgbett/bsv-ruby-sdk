# frozen_string_literal: true

module BSV
  module Transaction
    class P2PKH < UnlockingScriptTemplate
      ESTIMATED_SCRIPT_LENGTH = 107 # 1 + ~72 (DER sig+hashtype) + 1 + 33 (compressed pubkey)

      def initialize(private_key, sighash_type: Sighash::ALL_FORK_ID)
        super()
        @private_key = private_key
        @sighash_type = sighash_type
      end

      def sign(tx, input_index)
        hash = tx.sighash(input_index, @sighash_type)
        signature = @private_key.sign(hash)
        sig_with_hashtype = signature.to_der + [@sighash_type].pack('C')
        pubkey_bytes = @private_key.public_key.compressed
        BSV::Script::Script.p2pkh_unlock(sig_with_hashtype, pubkey_bytes)
      end

      def estimated_length(_tx, _input_index)
        ESTIMATED_SCRIPT_LENGTH
      end
    end
  end
end
