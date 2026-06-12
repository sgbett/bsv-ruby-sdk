# frozen_string_literal: true

module BSV
  module Transaction
    # Abstract base class for unlocking script templates.
    #
    # Templates provide deferred signing — an input can hold a template
    # that generates the unlocking script at sign time, when the full
    # transaction is available for sighash computation. Subclass and
    # implement {#sign} and {#estimated_length}.
    #
    # @abstract Subclass and override {#sign} and {#estimated_length}.
    # @see P2PKH
    class UnlockingScriptTemplate
      # Generate the unlocking script for a transaction input.
      #
      # @param _tx [Transaction::Tx] the transaction being signed
      # @param _input_index [Integer] the input index to sign
      # @return [Script::Script] the generated unlocking script
      # @raise [NotImplementedError] if not overridden by a subclass
      def sign(_tx, _input_index)
        raise NotImplementedError, "#{self.class}#sign must be implemented"
      end

      # Estimate the unlocking script length in bytes (for fee estimation).
      #
      # @param _tx [Transaction::Tx] the transaction
      # @param _input_index [Integer] the input index
      # @return [Integer] estimated script length in bytes
      # @raise [NotImplementedError] if not overridden by a subclass
      def estimated_length(_tx, _input_index)
        raise NotImplementedError, "#{self.class}#estimated_length must be implemented"
      end
    end
  end
end
