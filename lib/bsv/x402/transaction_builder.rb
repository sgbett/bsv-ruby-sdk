# frozen_string_literal: true

module BSV
  module X402
    # Builds a payment transaction that satisfies an x402 challenge.
    #
    # The builder is intentionally stateless — all configuration is passed
    # explicitly so that the same builder class can be used across different
    # payment contexts without shared mutable state.
    #
    # == Nonce UTXO
    #
    # The nonce UTXO is server-issued (invariant N-2). The client must spend it
    # to prove the payment is fresh and to prevent replay. Because the locking
    # script is determined by the server, the caller supplies a +nonce_unlocker+
    # callable that is responsible for generating the unlocking script for that
    # specific input.
    #
    # The default assumption is that the nonce UTXO is P2PKH-locked to the
    # client's key. To use a custom script, supply a lambda:
    #
    #   nonce_unlocker = ->(tx, idx) { MyCustomTemplate.new.sign(tx, idx) }
    #
    # == Funding UTXOs
    #
    # Additional UTXOs from the client's wallet cover the payment amount and
    # miner fee. Each funding UTXO hash must include:
    #
    #   { txid:, vout:, satoshis:, locking_script_hex:, private_key: }
    #
    # Funding inputs are signed with P2PKH using the +private_key+ on each UTXO.
    #
    # == Change
    #
    # If the total input value exceeds the payment amount plus fee, change is
    # returned to +change_locking_script_hex+. If that parameter is nil, or if
    # the change falls below the dust threshold (1 satoshi), the change output
    # is omitted and the surplus becomes additional fee.
    #
    # == Dust threshold
    #
    # Change below 1 satoshi is omitted. The built-in +Transaction#fee+ method
    # handles removal of change outputs that don't cover themselves.
    class TransactionBuilder
      # Minimum satoshi value for a change output. Anything below this is
      # absorbed into the miner fee.
      DUST_THRESHOLD = 1

      # Fee rate in satoshis per kilobyte used when no fee model is provided.
      # Matches the default in +BSV::Transaction::FeeModels::SatoshisPerKilobyte+.
      DEFAULT_FEE_RATE_SAT_PER_KB = 50

      # Build a payment transaction that satisfies +challenge+.
      #
      # @param challenge [Challenge] the x402 challenge to satisfy
      # @param funding_utxos [Array<Hash>] UTXOs to cover payment and fee
      #   Each: { txid:, vout:, satoshis:, locking_script_hex:, private_key: }
      # @param nonce_unlocker [#call] callable that returns a +Script::Script+
      #   unlocking the nonce input. Receives +(tx, input_index)+.
      # @param change_locking_script_hex [String, nil] locking script for change
      # @return [BSV::Transaction::Transaction] the signed transaction
      # @raise [InsufficientFundsError] when UTXOs cannot cover payment + fee
      # @raise [ChallengeExpiredError] when the challenge has already expired
      def self.build(challenge:, funding_utxos:, nonce_unlocker:, change_locking_script_hex: nil)
        raise ChallengeExpiredError, 'challenge has expired' if challenge.expired?

        tx = BSV::Transaction::Transaction.new

        # Add nonce UTXO as the first input. The nonce_unlocker will be called
        # during sign_all via the unlocking_script_template mechanism.
        nonce = challenge.nonce_utxo
        nonce_input = build_nonce_input(nonce, nonce_unlocker)
        tx.add_input(nonce_input)

        # Add client funding inputs.
        funding_utxos.each do |utxo|
          tx.add_input(build_funding_input(utxo))
        end

        # Payment output — the payee script and required amount from the challenge.
        payment_script = BSV::Script::Script.from_hex(challenge.payee_locking_script_hex)
        tx.add_output(
          BSV::Transaction::TransactionOutput.new(
            satoshis: challenge.amount_sats,
            locking_script: payment_script
          )
        )

        # Optional change output, flagged so +Transaction#fee+ can adjust it.
        if change_locking_script_hex
          change_script = BSV::Script::Script.from_hex(change_locking_script_hex)
          tx.add_output(
            BSV::Transaction::TransactionOutput.new(
              satoshis: 0,
              locking_script: change_script,
              change: true
            )
          )
        end

        # Calculate and apply fee; this also distributes change or removes the
        # change output if insufficient funds remain.
        total_input = nonce.satoshis + funding_utxos.sum { |u| u[:satoshis] }
        raise InsufficientFundsError, 'funding UTXOs insufficient to cover payment amount' if total_input < challenge.amount_sats

        tx.fee

        # After fee computation, check that we have not over-spent.
        non_change_outputs = tx.outputs.reject(&:change)
        required = non_change_outputs.sum(&:satoshis)
        raise InsufficientFundsError, 'funding UTXOs insufficient to cover payment plus fee' if total_input < required

        # Sign nonce input via its template, then sign funding inputs with P2PKH.
        tx.sign_all

        funding_utxos.each_with_index do |utxo, idx|
          # Funding inputs start at index 1 (after the nonce input at index 0).
          tx.sign(idx + 1, utxo[:private_key])
        end

        tx
      end

      # ------------------------------------------------------------------
      # Private helpers
      # ------------------------------------------------------------------

      # Build the nonce input with an unlocking script template that delegates
      # to the caller-supplied +nonce_unlocker+ callable.
      #
      # @param nonce [NonceUTXO]
      # @param nonce_unlocker [#call]
      # @return [BSV::Transaction::TransactionInput]
      def self.build_nonce_input(nonce, nonce_unlocker)
        input = BSV::Transaction::TransactionInput.new(
          prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex(nonce.txid),
          prev_tx_out_index: nonce.vout
        )
        input.source_satoshis = nonce.satoshis
        input.source_locking_script = BSV::Script::Script.from_hex(nonce.locking_script_hex)
        input.unlocking_script_template = CallableUnlockingTemplate.new(nonce_unlocker)
        input
      end
      private_class_method :build_nonce_input

      # Build a funding input from a client UTXO hash.
      #
      # @param utxo [Hash] { txid:, vout:, satoshis:, locking_script_hex:, private_key: }
      # @return [BSV::Transaction::TransactionInput]
      def self.build_funding_input(utxo)
        input = BSV::Transaction::TransactionInput.new(
          prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex(utxo[:txid]),
          prev_tx_out_index: utxo[:vout]
        )
        input.source_satoshis = utxo[:satoshis]
        input.source_locking_script = BSV::Script::Script.from_hex(utxo[:locking_script_hex])
        input
      end
      private_class_method :build_funding_input

      # Minimal +UnlockingScriptTemplate+ wrapper around an arbitrary callable.
      #
      # Allows any +#call(tx, input_index)+  lambda or object to participate in
      # the deferred +sign_all+ signing flow without requiring a named subclass
      # of +P2PKH+.
      class CallableUnlockingTemplate < BSV::Transaction::UnlockingScriptTemplate
        # @param callable [#call] must respond to +call(tx, input_index)+
        def initialize(callable)
          super()
          @callable = callable
        end

        # @param tx [BSV::Transaction::Transaction]
        # @param input_index [Integer]
        # @return [BSV::Script::Script]
        def sign(tx, input_index)
          @callable.call(tx, input_index)
        end

        # @return [Integer] conservative upper bound for fee estimation
        def estimated_length(_tx, _input_index)
          BSV::Transaction::P2PKH::ESTIMATED_SCRIPT_LENGTH
        end
      end
    end
  end
end
