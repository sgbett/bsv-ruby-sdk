# frozen_string_literal: true

require_relative 'error'
require_relative 'script_number'
require_relative 'stack'

module BSV
  module Script
    class Interpreter
      attr_reader :dstack, :astack

      # Evaluate unlock + lock scripts without transaction context.
      # Signature operations will always fail (no sighash available).
      def self.evaluate(unlock_script, lock_script)
        new(
          unlock_script: unlock_script,
          lock_script: lock_script
        ).execute
      end

      # Verify a transaction input by evaluating its scripts.
      def self.verify(tx:, input_index:, unlock_script:, lock_script:, satoshis:)
        new(
          unlock_script: unlock_script,
          lock_script: lock_script,
          tx: tx,
          input_index: input_index,
          satoshis: satoshis
        ).execute
      end

      private

      def initialize(unlock_script:, lock_script:, tx: nil, input_index: nil, satoshis: nil)
        @unlock_script = unlock_script
        @lock_script = lock_script
        @tx = tx
        @input_index = input_index
        @satoshis = satoshis

        @dstack = Stack.new
        @astack = Stack.new
        @cond_stack = []
        @else_stack = []
        @last_code_sep = 0
        @early_return = false
      end

      def execute
        raise NotImplementedError, 'execution loop added in Phase 2'
      end
    end
  end
end
