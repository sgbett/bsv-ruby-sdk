# frozen_string_literal: true

module BSV
  module X402
    # Duck-type interface for nonce UTXO providers.
    #
    # Any object that responds to +reserve_nonce+ satisfies this interface.
    # Implementations are responsible for atomically reserving a fresh nonce
    # UTXO so that it cannot be issued to two clients simultaneously
    # (invariant N-3).
    #
    # The returned hash must contain the following string or symbol keys:
    #   - +txid+               — transaction ID of the nonce UTXO
    #   - +vout+               — output index
    #   - +satoshis+           — value in satoshis (must be > 0)
    #   - +locking_script_hex+ — hex-encoded locking script
    #
    # Include this module in a concrete provider class to document intent.
    # The module provides a default +reserve_nonce+ that raises +NotImplementedError+.
    module NonceProvider
      # Atomically reserves and returns a fresh nonce UTXO.
      #
      # @return [Hash] hash with keys: txid, vout, satoshis, locking_script_hex
      # @raise [NotImplementedError] if not overridden by the including class
      def reserve_nonce
        raise NotImplementedError, "#{self.class}#reserve_nonce is not implemented"
      end
    end

    # A simple nonce provider that always returns a fixed +NonceUTXO+.
    #
    # Intended for testing and development. Not suitable for production use
    # because the same nonce UTXO would be issued to every requester,
    # violating invariant N-3 (atomic reservation).
    class StaticNonceProvider
      include NonceProvider

      # @param nonce_utxo [NonceUTXO] the fixed nonce UTXO to return
      def initialize(nonce_utxo)
        @nonce_utxo = nonce_utxo
      end

      # Returns the fixed nonce UTXO on every call.
      #
      # @return [NonceUTXO]
      def reserve_nonce
        @nonce_utxo
      end
    end
  end
end
